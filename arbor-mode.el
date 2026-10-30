;;; arbor-mode.el --- Edit Arbor source files -*- lexical-binding: t; -*-

;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: languages

;;; Commentary:

;; A small major mode for writing Arbor examples while its compiler and syntax
;; evolve.  It uses only Emacs built-ins.  Interpolation is experimental syntax,
;; following the examples in the language-design discussion.
;;
;; Syntax properties distinguish strings from code, including nested templates.
;; This first version reparses the buffer on edits, favoring clarity and correct
;; lexical context over performance on large source files.

;;; Code:

(require 'cl-lib)
(require 'font-lock)
(require 'syntax)

(defgroup arbor nil
  "Editing Arbor source code."
  :group 'languages)

(defcustom arbor-indent-offset 4
  "Number of columns per level of bracket nesting."
  :type 'integer
  :safe #'natnump
  :group 'arbor)

(defvar arbor-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?_ "w" table)
    (modify-syntax-entry ?\( "()" table)
    (modify-syntax-entry ?\) ")(" table)
    (modify-syntax-entry ?\[ "(]" table)
    (modify-syntax-entry ?\] ")[" table)
    (modify-syntax-entry ?\{ "(}" table)
    (modify-syntax-entry ?\} "){" table)
    ;; Quotes become string fences only when the lexical scanner marks them.
    ;; This keeps quotes inside a different kind of string from ending it.
    (modify-syntax-entry ?\" "." table)
    (modify-syntax-entry ?\' "." table)
    (modify-syntax-entry ?\\ "\\" table)
    (modify-syntax-entry ?/ ". 12b" table)
    (modify-syntax-entry ?\n "> b" table)
    table)
  "Syntax table used by `arbor-mode'.")

(cl-defstruct (arbor--context (:constructor arbor--context-create))
  "A lexical context: ordinary code or the contents of a string."
  kind delimiter interpolate terminal start (depth 0))

(defconst arbor--identifier "[[:alpha:]_][[:alnum:]_]*")

(defun arbor--fence (position)
  "Mark the character at POSITION as a generic string delimiter."
  (put-text-property position (1+ position)
                     'syntax-table (string-to-syntax "|")))

(defun arbor--syntax-extend-region (start end)
  "Extend START and END to the buffer boundaries when necessary."
  (unless (and (= start (point-min)) (= end (point-max)))
    (cons (point-min) (point-max))))

(defun arbor--syntax-propertize (start end)
  "Apply lexical syntax properties between START and END.
The region-extension hook supplies the whole buffer.  A stack permits strings
inside interpolation, and interpolation inside nested strings."
  (save-excursion
    (with-silent-modifications
      (remove-text-properties
       start end '(syntax-table nil syntax-multiline nil
                   arbor-terminal-control nil arbor-interpolation-delimiter nil))
      (goto-char start)
      (let ((stack (list (arbor--context-create :kind 'code))))
        (cl-labels
            ((open-string
              (delimiter interpolate terminal)
              (let ((begin (point)))
                (arbor--fence begin)
                (forward-char (length delimiter))
                (push (arbor--context-create
                       :kind 'string :delimiter delimiter
                       :interpolate interpolate :terminal terminal :start begin)
                      stack))))
          (while (< (point) end)
            (let ((context (car stack)))
              (if (eq (arbor--context-kind context) 'code)
                  (cond
                   ((looking-at "//") (forward-line 1))
                   ((looking-at "\"\"\"") (open-string "\"\"\"" nil nil))
                   ((eq (char-after) ?\") (open-string "\"" nil nil))
                   ((looking-at arbor--identifier)
                    (let ((prefix (match-string-no-properties 0)))
                      (goto-char (match-end 0))
                      (cond
                       ((eq (char-after) ?\')
                        (open-string "'" (member prefix '("term" "t"))
                                     (equal prefix "term")))
                       ((and (equal prefix "f") (eq (char-after) ?\"))
                        (open-string (if (looking-at "\"\"\"") "\"\"\"" "\"")
                                     t nil)))))
                   ((and (arbor--context-interpolate context)
                         (eq (char-after) ?\{))
                    (cl-incf (arbor--context-depth context))
                    (forward-char 1))
                   ((and (arbor--context-interpolate context)
                         (eq (char-after) ?\}))
                    (if (> (arbor--context-depth context) 0)
                        (cl-decf (arbor--context-depth context))
                      (arbor--fence (point))
                      (put-text-property (point) (1+ (point))
                                         'arbor-interpolation-delimiter t)
                      (pop stack))
                    (forward-char 1))
                   (t (forward-char 1)))
                (cond
                 ;; Backslash escapes protect the following character.
                 ((eq (char-after) ?\\)
                  (forward-char (min 2 (- end (point)))))
                 ((looking-at (regexp-quote (arbor--context-delimiter context)))
                  (forward-char (length (arbor--context-delimiter context)))
                  (arbor--fence (1- (point)))
                  (put-text-property (arbor--context-start context) (point)
                                     'syntax-multiline t)
                  (pop stack))
                 ;; ${red} is a style directive, not an interpolation.  Escaped
                 ;; dollar runs such as $${red} also stay literal string text.
                 ((and (arbor--context-terminal context)
                       (looking-at
                        (concat "\\$+\\(?:{" arbor--identifier "}\\|"
                                arbor--identifier "\\)?")))
                  (let ((begin (point))
                        (finish (match-end 0)))
                    (unless (eq (char-after (1+ begin)) ?$)
                      (put-text-property begin finish 'arbor-terminal-control t))
                    (goto-char finish)))
                 ((and (arbor--context-interpolate context)
                       (or (looking-at "{{") (looking-at "}}")))
                  (forward-char 2))
                 ((and (arbor--context-interpolate context)
                       (eq (char-after) ?\{))
                  (arbor--fence (point))
                  (put-text-property (point) (1+ (point))
                                     'arbor-interpolation-delimiter t)
                  (forward-char 1)
                  (push (arbor--context-create :kind 'code :interpolate t) stack))
                 (t (forward-char 1))))))
          ;; Keep incomplete strings useful while the user is still typing.
          (dolist (context stack)
            (when (eq (arbor--context-kind context) 'string)
              (put-text-property (arbor--context-start context) end
                                 'syntax-multiline t))))))))

(defun arbor--match-property (property limit)
  "Find the next run of PROPERTY before LIMIT for font locking."
  (let ((begin (text-property-any (point) limit property t)))
    (when begin
      (let ((end (next-single-property-change begin property nil limit)))
        (set-match-data (list begin end))
        (goto-char end)
        t))))

(defun arbor--match-terminal-control (limit)
  "Match a terminal style control before LIMIT."
  (arbor--match-property 'arbor-terminal-control limit))

(defun arbor--match-interpolation-delimiter (limit)
  "Match an interpolation delimiter before LIMIT."
  (arbor--match-property 'arbor-interpolation-delimiter limit))

(defconst arbor--font-lock-keywords
  (let ((keywords
         '("fun" "pure" "let" "var" "const" "class" "extends" "mixin"
           "enum" "type" "choice" "protocol" "mut" "frozen" "immutable"
           "unsafe" "if" "else" "switch" "case" "for" "while" "loop" "in"
           "break" "continue" "return" "throw" "warn" "try" "except" "finally"
           "with" "as" "async" "await" "use" "super" "import" "from" "not"
           "and" "or" "is" "validate" "ensures" "requires" "throws"))
        (types
         '("bool" "int" "float" "bigint" "decimal" "fraction" "rational"
           "string" "list" "tuple" "map" "set" "file" "NoReturn" "Self"
           "i8" "i16" "i32" "i64" "i128" "u8" "u16" "u32" "u64" "u128"
           "f32" "f64" "f128")))
    `((,(concat "@" arbor--identifier) . font-lock-preprocessor-face)
      (,(concat "\\_<fun\\_>\\s-+\\(" arbor--identifier "\\)")
       1 font-lock-function-name-face)
      (,(concat "\\_<\\(?:class\\|enum\\|protocol\\|type\\|choice\\)"
                "\\_>\\s-+\\(" arbor--identifier "\\)")
       1 font-lock-type-face)
      (,(concat "\\_<\\(?:let\\|var\\|const\\)\\_>\\s-+\\("
                arbor--identifier "\\)")
       1 font-lock-variable-name-face)
      (,(regexp-opt keywords 'symbols) . font-lock-keyword-face)
      (,(regexp-opt '("true" "false" "null" "sentinel" "void") 'symbols)
       . font-lock-constant-face)
      (,(regexp-opt types 'symbols) . font-lock-type-face)
      (,(concat "\\_<\\(" arbor--identifier "\\)['\"]")
       1 font-lock-builtin-face)
      ("\\_<[0-9]+\\(?:\\.[0-9]+\\)?\\(?:[eE][+-]?[0-9]+\\)?\\_>"
       . font-lock-constant-face)
      (,(concat "\\_<\\(" arbor--identifier "\\)\\s-*(")
       1 font-lock-function-name-face)
      (arbor--match-terminal-control (0 font-lock-builtin-face t))
      (arbor--match-interpolation-delimiter (0 font-lock-preprocessor-face t))))
  "Font-lock rules for Arbor source code.")

(defun arbor--font-lock-extend-region ()
  "Extend fontification to the buffer after a lexical-context change."
  (let ((changed (or (/= font-lock-beg (point-min))
                     (/= font-lock-end (point-max)))))
    (setq font-lock-beg (point-min)
          font-lock-end (point-max))
    changed))

(defun arbor-indent-line ()
  "Indent the current line by bracket depth, preserving string contents."
  (interactive)
  (let* ((offset (- (current-column) (current-indentation)))
         (state (syntax-ppss (line-beginning-position)))
         (indent
          (if (nth 3 state)
              (current-indentation)
            (save-excursion
              (back-to-indentation)
              (* arbor-indent-offset
                 (max 0 (- (car state) (if (looking-at "[])}]") 1 0))))))))
    (indent-line-to indent)
    (when (> offset 0)
      (move-to-column (+ indent offset)))))

;;;###autoload
(define-derived-mode arbor-mode prog-mode "Arbor"
  "Major mode for Arbor examples and source files.
Provide syntax highlighting, // comments, and basic bracket indentation.
Template interpolation follows the provisional syntax in the design discussion."
  :syntax-table arbor-mode-syntax-table
  (setq-local font-lock-defaults '(arbor--font-lock-keywords))
  (setq-local font-lock-multiline t)
  (setq-local syntax-propertize-function #'arbor--syntax-propertize)
  (add-hook 'syntax-propertize-extend-region-functions
            #'arbor--syntax-extend-region nil t)
  (add-hook 'font-lock-extend-region-functions
            #'arbor--font-lock-extend-region nil t)
  (setq-local indent-line-function #'arbor-indent-line)
  (setq-local indent-tabs-mode nil)
  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-start-skip "//+\\s-*")
  (setq-local parse-sexp-ignore-comments t)
  (syntax-propertize (point-max)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.arb\\'" . arbor-mode))

(provide 'arbor-mode)
;;; arbor-mode.el ends here
