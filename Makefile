EMACS ?= emacs

.PHONY: test compile

test:
	$(EMACS) -Q --batch -L . -l test/arbor-mode-test.el -f ert-run-tests-batch-and-exit

compile:
	$(EMACS) -Q --batch -L . -f batch-byte-compile arbor-mode.el
