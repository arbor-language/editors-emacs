;;; arbor-mode-test.el --- Tests for Arbor editing -*- lexical-binding: t; -*-

(require 'ert)
(require 'arbor-mode)

(defmacro arbor-test--with-buffer (source &rest body)
  "Run BODY in a fontified Arbor buffer containing SOURCE."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (insert ,source)
     (arbor-mode)
     (font-lock-mode 1)
     (font-lock-ensure)
     ,@body))

(defun arbor-test--position (text)
  "Return the beginning of the first occurrence of TEXT."
  (let ((case-fold-search nil))
    (save-excursion
      (goto-char (point-min))
      (search-forward text)
      (match-beginning 0))))

(defun arbor-test--string-p (text)
  "Return non-nil when TEXT begins inside a string."
  (nth 3 (syntax-ppss (arbor-test--position text))))

(defun arbor-test--face-p (text face)
  "Return non-nil when the first character of TEXT has FACE."
  (let ((actual (get-text-property (arbor-test--position text) 'face)))
    (if (listp actual) (memq face actual) (eq face actual))))

(ert-deftest arbor-file-association ()
  (with-temp-buffer
    (setq buffer-file-name "/tmp/arbor-mode-example.arb")
    (set-auto-mode)
    (should (eq major-mode 'arbor-mode))))

(ert-deftest arbor-declaration-faces ()
  (arbor-test--with-buffer
      "pure fun add(x: int) -> int { let answer = true; }"
    (should (arbor-test--face-p "pure" 'font-lock-keyword-face))
    (should (arbor-test--face-p "add" 'font-lock-function-name-face))
    (should (arbor-test--face-p "answer" 'font-lock-variable-name-face))
    (should (arbor-test--face-p "int" 'font-lock-type-face))
    (should (arbor-test--face-p "true" 'font-lock-constant-face))))

(ert-deftest arbor-comments-do-not-open-strings ()
  (arbor-test--with-buffer "// term'bad { \"\nlet after = 1;"
    (should (nth 4 (syntax-ppss (arbor-test--position "bad"))))
    (should (arbor-test--face-p "bad" 'font-lock-comment-face))
    (should-not (arbor-test--string-p "after"))))

(ert-deftest arbor-prefixed-literals ()
  (arbor-test--with-buffer
      "let day = date'2000-01-01'; let key = secret'abc'; let after = 1;"
    (should (arbor-test--string-p "2000"))
    (should (arbor-test--string-p "abc"))
    (should-not (arbor-test--string-p "after"))))

(ert-deftest arbor-apostrophe-in-double-quoted-string ()
  (arbor-test--with-buffer "let x = \"it's okay\"; let after = 1;"
    (should (arbor-test--string-p "okay"))
    (should-not (arbor-test--string-p "after"))))

(ert-deftest arbor-triple-quoted-strings ()
  (arbor-test--with-buffer
      "let x = \"\"\"first \"quoted\"\nfun not_a_definition\n\"\"\"; let after = 1;"
    (should (arbor-test--string-p "quoted"))
    (should (arbor-test--face-p "not_a_definition" 'font-lock-string-face))
    (should-not (arbor-test--string-p "after"))))

(ert-deftest arbor-nested-timestamp-example ()
  (arbor-test--with-buffer
      "let letter = term'{datetime'2026-01-01T00:00:00Z'.to_timestamp()}'; let after = 1;"
    (should-not (arbor-test--string-p "datetime"))
    (should (arbor-test--string-p "2026"))
    (should-not (arbor-test--string-p "to_timestamp"))
    (should (arbor-test--face-p "to_timestamp" 'font-lock-function-name-face))
    (should-not (arbor-test--string-p "after"))))

(ert-deftest arbor-nested-terminal-literals ()
  (arbor-test--with-buffer
      "let x = term'Outer {format(term'Inner {name}')} done'; let after = 1;"
    (dolist (text '("Outer" "Inner" "done"))
      (should (arbor-test--string-p text)))
    (dolist (text '("format" "name" "after"))
      (should-not (arbor-test--string-p text)))))

(ert-deftest arbor-braces-inside-interpolation ()
  (arbor-test--with-buffer
      "let x = term'Value {lookup({\"key\": value})} done'; let after = 1;"
    (should (arbor-test--string-p "key"))
    (should-not (arbor-test--string-p "value"))
    (should (arbor-test--string-p "done"))
    (should-not (arbor-test--string-p "after"))))

(ert-deftest arbor-comments-inside-interpolation ()
  (arbor-test--with-buffer
      "let x = term'{format(// } and a quote '\nvalue)} done'; let after = 1;"
    (should (nth 4 (syntax-ppss (arbor-test--position "and"))))
    (should-not (arbor-test--string-p "value"))
    (should (arbor-test--string-p "done"))
    (should-not (arbor-test--string-p "after"))))

(ert-deftest arbor-style-controls-are-not-interpolations ()
  (arbor-test--with-buffer "let x = term'$bold${red}Error$reset {account_id}';"
    (should (arbor-test--string-p "red"))
    (should (arbor-test--face-p "$bold" 'font-lock-builtin-face))
    (should (arbor-test--face-p "${red}" 'font-lock-builtin-face))
    (should-not (arbor-test--string-p "account_id"))))

(ert-deftest arbor-escaped-dollar-controls ()
  (arbor-test--with-buffer "let x = term'$${red} $$$company_error';"
    (should (arbor-test--string-p "red"))
    (should-not (arbor-test--face-p "$${red}" 'font-lock-builtin-face))
    (should-not (arbor-test--face-p "$$$company_error" 'font-lock-builtin-face))))

(ert-deftest arbor-f-string-and-deferred-template ()
  (arbor-test--with-buffer
      "let a = f\"Hello {name}\"; let b = t'Welcome {person}'; let after = 1;"
    (should (arbor-test--string-p "Hello"))
    (should-not (arbor-test--string-p "name"))
    (should-not (arbor-test--string-p "person"))
    (should-not (arbor-test--string-p "after"))))

(ert-deftest arbor-escaped-braces-remain-string-text ()
  (arbor-test--with-buffer "let a = f\"{{literal}} {value}\";"
    (should (arbor-test--string-p "literal"))
    (should-not (arbor-test--string-p "value"))))

(ert-deftest arbor-edits-update-string-boundaries ()
  (arbor-test--with-buffer "let day = date'2000';\nlet after = 1;"
    (goto-char (point-min))
    (search-forward "2000")
    (let ((closing (point)))
      (delete-char 1)
      (font-lock-flush)
      (font-lock-ensure)
      (should (arbor-test--string-p "after"))
      (goto-char closing)
      (insert "'")
      (font-lock-flush)
      (font-lock-ensure)
      (should-not (arbor-test--string-p "after")))))

(ert-deftest arbor-basic-indentation ()
  (arbor-test--with-buffer "fun main() {\nif true {\nwrite(1);\n}\n}\n"
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string)
                   "fun main() {\n    if true {\n        write(1);\n    }\n}\n"))))

(ert-deftest arbor-indentation-preserves-string-contents ()
  (arbor-test--with-buffer "let x = \"\"\"first\n  deliberate indentation\n\"\"\";\n"
    (let ((before (buffer-string)))
      (indent-region (point-min) (point-max))
      (should (equal before (buffer-string))))))

(ert-deftest arbor-unicode-binding-name ()
  (arbor-test--with-buffer "let café = 1;"
    (should (arbor-test--face-p "café" 'font-lock-variable-name-face))))

;;; arbor-mode-test.el ends here
