test: build/vader.vim
	cd tests && vim -Nu vimrc -c 'Vader! *.vader'
.PHONY: test

testi: build/vader.vim
	cd tests && vim -Nu vimrc -c 'Vader *.vader'
.PHONY: testi

build/vader.vim:
	git clone https://github.com/junegunn/vader.vim $@
