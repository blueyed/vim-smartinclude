" Use this via after?
" if exists('b:undo_ftplugin')
"   let b:undo_ftplugin .= '|'
" else
"   let b:undo_ftplugin = ''
" endif
" let b:undo_ftplugin .= 'unlet b:textobj_function_select'
"
" See also 'suffixesadd', used to add suffixes for `gf`.


" Defaults for every buffer.
if !exists('g:smartinclude_expr_stack')
  " XXX: defaults ?!
  " strip prefix from `git diff` when looking up a filename
  " au FileType diff * set includeexpr=substitute(v:fname,'^[abwi]/','','')

  " A list of [use_sandbox, expr]: use_sandbox is 1 for when it was set from a
  " modeline, and will execute it using :sandbox then.
  let g:smartinclude_expr_stack = []
endif

" Debugging {{{
if !exists('g:smartinclude_debug')
  let g:smartinclude_debug = 0
endif
fun! s:debug(msg)
  if !g:smartinclude_debug
    return
  endif
  " NOTE: flickers! / slow
  " redraw
  echom a:msg
endfun
" }}}

function! LookupInPaths(fname)
  " Look in current files directory first.
  let r = findfile(a:fname, '.')
  if filereadable(r)
    return fnamemodify(r, ':p')
  endif

  " Look in current files directory first.
  let r = findfile(a:fname, fnamemodify(bufname('%'), ':h'))
  if filereadable(r)
    return fnamemodify(r, ':p')
  endif

  let r = findfile(a:fname)
  if filereadable(r)
    " NOTE: gets done for Ctrl-P, too.
    " echoerr "SmartIncludeExpr: should never happen?! - because a standard find gets done before..?!"
    " echoerr "a:fname" a:fname
    return fnamemodify(r, ':p')
  endif
  return ""
endfunction


" Lookup in Django projects. {{{
" Use pyeval() or py3eval() for newer python versions or fall back to
" vim.command() if vim version is old
" This code is borrowed from ctrlp-cmatcher / Powerline.
let s:pycmd = has('python3') ? 'py3' : 'py'
let s:_pyeval = s:pycmd.'eval'

if exists('*'. s:_pyeval)
  let s:pyeval = function(s:_pyeval)
else
  exec s:pycmd 'import json, vim'
  exec "function! s:pyeval(e)\n".
  \   s:pycmd." vim.command('return ' + json.dumps(eval(vim.eval('a:e'))))\n".
  \"endfunction"
endif
" com! PythonSmartInclude python3


let s:done_define_django_find_template = 0
function! s:define_django_find_template()
  if s:done_define_django_find_template
    return
  endif
  exec s:pycmd "import vim"
  exec s:pycmd "import django; django.setup()"
  exec s:pycmd "from django.template import loader, TemplateDoesNotExist"
  exec s:pycmd "def django_find_template(s):\n
        \ try:\n
        \     t = loader.get_template(s)\n
        \ except TemplateDoesNotExist:\n
        \     pass\n
        \ return t.origin.name if t else None\n"
  let s:done_define_django_find_template = 1
endfunction

function! s:django_find_template(s)
  call s:define_django_find_template()
  return s:pyeval('django_find_template("'.escape(a:s, '"').'")')
endfunction
" }}}


" Setup &includeexpr to look at various locations. {{{
" TODO: lookup_into_path: do not collect all, but look into them directly.
" NOTE: gets called for i_CTRL-P completion, too!
function! SmartIncludeExpr(fname)
  call s:debug("SmartIncludeExpr: fname: ".a:fname)
  " Call any functions in smartinclude_expr_stack first.
  for [from_modeline, iexpr] in g:smartinclude_expr_stack
    let iexpr = substitute(iexpr, 'v:fname', 'a:fname', 'g')
    if from_modeline
      call s:debug(printf('SmartIncludeExpr: calling %s (in sandbox)', iexpr))
      try
        sandbox let r = eval(iexpr)
      catch
        echohl ErrorMsg
        echom printf('Failed to execute includeexpr in sandbox (%s): %s', iexpr, v:errmsg)
        echohl None
      endtry
    else
      call s:debug(printf('SmartIncludeExpr: calling %s', iexpr))
      let r = eval(iexpr)
    endif
    call s:debug(printf('SmartIncludeExpr: returned: %s', r))
    " NOTE: fugitive:// is not readable.
    if len(r)
      return r
    endif
  endfor

  let r = LookupInPaths(a:fname)
  if len(r) | return r | endif

  if index(['htmldjango', 'django'], &ft) != -1
    let r = s:django_find_template(a:fname)
    if len(r) | return r | endif
  endif

  " Look for fname with leading slash removed (html references, e.g. css).
  if a:fname[0] == '/'
    let r = LookupInPaths(findfile(a:fname[1:]))
    if len(r) | return r | endif
  endif

  " Strip prefix from `git diff` (or diff in general) when looking up a
  " filename.
  " TODO: limit this to a single char? "a/", "b/" (diff),
  "       "i/", "w/" (normal git diff).
  let r = substitute(a:fname, '^\S\{-}/', '', '')
  call s:debug("Before LookupInPaths: ".r)
  let r = LookupInPaths(r)
  if len(r) | return r | endif

  " Remove any '-r' prefix (pip requirements).
  if a:fname[0:1] == '-r'
    let r = findfile(a:fname[2:])
    let r = LookupInPaths(r)
    if len(r) | return r | endif
  endif

  " Mangle filename for scss/sass: extension and "_" prefix.
  if &ft == "scss" || &ft == "sass"
    for ext in ["scss", "sass"]
      let r = a:fname
      " Append extension.
      if fnamemodify(r, ':e') == ""
        let r = r.'.'.ext
        let r1 = LookupInPaths(r)
        if len(r1) | return r | endif
      endif
      " Prepend "_" to basename
      if fnamemodify(r, ':t')[0] != "_"
        let r = substitute(r, '[^/]\+$', '_\0', '')
        let r2 = LookupInPaths(r)
        if len(r2) | return r | endif
      endif
      call s:debug("Tried ".r." for ".ext)
    endfor
  endif

  " Finally, lookup dir lists (virtualenv, python path) and add matching
  " entries to Vim's path (where gf looks at afterwards)
  " XXX: PYTHON_PATH for python/htmldjango only?
  let g:lookup_into_path = []
  " if len($VIRTUAL_ENV)
  "   " TODO: slow! use find with maxdepth
  "   let g:lookup_into_path += split(system("find -L $VIRTUAL_ENV -type d -name templates -maxdepth 3'), '\\n')
  " endif

  " Not that useful: gf-python is better
  " if len($PYTHON_PATH)
  "   let g:lookup_into_path += split($PYTHON_PATH, ':')
  " endif

  " Look at project root.
  if exists('*ProjectRootGuess')
    let rr = ProjectRootGuess()
    if len(rr)
      " Look at file in repo root.
      let r = rr . a:fname
      let r = LookupInPaths(r)
      if len(r) | return r | endif
    endif
  endif

  " XXX: slow! use find with maxdepth
  " XXX: would require changing the filename for templatetag
  " for dirinroot in ['templatetags', 'templates']
  "   " let g:lookup_into_path += glob(rr.'/**/'.dirinroot, 0, 1)
  "   " Find dirs in root and sort them by number of slashes/segments and
  "   " length: nearest first.
  "   let cmd = 'find '.shellescape(rr).' -type d -name '.shellescape(dirinroot).' -maxdepth 10'
  "         \ .'| awk ''{print split($0, a, "/"), length, $0}'' | sort -n | cut -d " " -f3-'
  "   call s:debug("SmartIncludeExpr: calling: ".cmd)
  "   let g:lookup_into_path += split(system(cmd), '\n')
  " endfor

  " Add / handle marker used for auto-added dirs
  call SmartIncludeCleanPath()
  let &l:path .= ',SMARTSEP'

  " Add entries to path, where the file exists, so `gf` will pick it up.
  for p in g:lookup_into_path
    let fn = p.'/'.a:fname
    if filereadable(fn) | let &l:path .= ','.p | endif
  endfor
  return a:fname
endfunction

" Clean path: this will get rebuild via a call to SmartIncludeExpr.
fun! SmartIncludeCleanPath()
  if &l:path =~ ',SMARTSEP'
    let &l:path = substitute(&l:path, ',SMARTSEP.*', '', '')
  endif
endfun
command! SmartIncludeCleanPath call SmartIncludeCleanPath()

fun! SmartIncludeSetIncludeExpr()
  if !exists('b:smartinclude_expr_stack')
    let b:smartinclude_expr_stack = g:smartinclude_expr_stack
  endif

  " Move any b:includeexpr onto the stack.
  if len(&l:includeexpr) && &l:includeexpr !=# 'SmartIncludeExpr(v:fname)'
    redir => out
      silent verbose setlocal includeexpr?
    redir END
    let from_modeline = out =~# 'Last set from modeline' ? 1 : 0
    let add = [from_modeline, &l:includeexpr]
    if index(g:smartinclude_expr_stack, add) == -1
      if from_modeline
        " Remove any other entry set from modeline before.
        call filter(b:smartinclude_expr_stack, 'v:val[0] == 0')
      endif
      let b:smartinclude_expr_stack = add(b:smartinclude_expr_stack, add)
    endif
  endif

  setlocal includeexpr=SmartIncludeExpr(v:fname)
endfun

fun! SmartIncludeSetup(event)
  " Do not return here: otherwise other ftplugins overrule us.
  " if exists('b:smartinclude_did_setup')
  "   call s:debug('SmartIncludeSetup: b:smartinclude_did_setup==1. Return.')
  "   return
  " endif

  call s:debug('SmartIncludeSetup: ['.expand('%:t').']: '
        \ .'on: '.a:event
        \ .', ft: '.&filetype
        \ .', did_ftplugin: '.(exists('b:did_ftplugin') ? b:did_ftplugin : '-')
        \ .', includeexpr: '.&l:includeexpr)
        " \ .", undo_ftplugin: ".(exists('b:undo_ftplugin') ? b:undo_ftplugin : '-')

  if a:event ==# 'FileType'
    " Remember any previously set includeexpr.
    " STEP 1: called before any ftplugin/*.vim.
    if !exists('b:smartinclude_setup_ft')
      " let b:smartinclude_orig = &l:includeexpr
      let b:smartinclude_setup_ft = &ft
    endif

    if exists('b:did_ftplugin') && b:did_ftplugin
      call SmartIncludeSetIncludeExpr()
    endif

  elseif a:event ==# 'BufEnter' || a:event ==# 'OptionSet'
    " This gets called after any ftplugin/*.vim.
    call SmartIncludeSetIncludeExpr()
    let b:smartinclude_did_setup = 1
  endif
endfun

augroup SmartInclude
  au!
  au BufEnter *    call SmartIncludeSetup('BufEnter')
  au FileType *    call SmartIncludeSetup('FileType')
  if exists('##OptionSet')
    au OptionSet includeexpr call SmartIncludeSetup('OptionSet')
  endif
  au BufWinEnter * call SmartIncludeCleanPath()
augroup END

" vim: fdm=marker sw=2 et
