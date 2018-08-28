ifeq ($(TEST_VIM),nvim)
	export VADER_OUTPUT_FILE:=/dev/stderr
	override TEST_VIM:=nvim --headless
else
	TEST_VIM:=vim
endif

test: build/vader.vim
	cd tests && $(TEST_VIM) -Nu vimrc -c 'Vader! *.vader'
.PHONY: test

testi: build/vader.vim
	cd tests && $(TEST_VIM) -Nu vimrc -c 'Vader *.vader'
.PHONY: testi

build/vader.vim:
	git clone https://github.com/junegunn/vader.vim $@
