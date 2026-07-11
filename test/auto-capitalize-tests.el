;;; auto-capitalize-tests.el --- Tests for auto-capitalize.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Abdulnafé Toulaïmat

;; Author: Abdulnafé Toulaïmat <abdulnafe.toulaimat@gmail.com>
;; Keywords:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'ert)
(require 'ert-x)                        ; For `ert-simulate-command'
(require 'auto-capitalize)
(require 'auto-capitalize-org)
(when (featurep 'auctex)
  (require 'auto-capitalize-tex))
(require 'font-lock)                    ; For `font-lock-ensure', `font-lock-mode'

(defmacro auto-capitalize-tests--setup (mode &rest body)
  "Set up a buffer for auto-capitalize-tests."
  `(ert-with-test-buffer
       (:name "*auto-capitalize-tests*"
              :selected t)
     (,mode)
     (auto-capitalize-mode 1)
     (when (and (derived-mode-p 'TeX-mode)
                (fboundp 'auto-capitalize-tex-mode))
       (auto-capitalize-tex-mode 1))
     (when (and (derived-mode-p 'org-mode)
                (fboundp 'auto-capitalize-org-mode))
       (auto-capitalize-org-mode 1))
     (font-lock-mode 1)
     (progn ,@body)))


;;;; Tests for `text-mode'

(ert-deftest auto-capitalize-text-bob ()
  "Capitalize the first word in a `text-mode' buffer."
  (auto-capitalize-tests--setup
   text-mode
   (goto-char (point-min))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max)) "A "))))

(ert-deftest auto-capitalize-text-triggers ()
  "Capitalize the previous word after `auto-capitalize-trigger-chars'."
  (auto-capitalize-tests--setup
    text-mode
    (electric-quote-local-mode -1)
    (dolist (trigger auto-capitalize-trigger-chars)
      (erase-buffer)
      (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
      (ert-simulate-command '(self-insert-command 1 ?a))
      (ert-simulate-command `(self-insert-command 1 ,trigger))
      (should (equal (buffer-substring-no-properties (point-min) (point-max))
                     (concat "\nA" (char-to-string trigger)))))))

(ert-deftest auto-capitalize-text-yank ()
  "Capitalize yanked text."
  (auto-capitalize-tests--setup
    text-mode
    (let* ((sep (if sentence-end-double-space "  " " "))
           (old-kill-ring kill-ring)
           (old-kill-ring-yank-pointer kill-ring-yank-pointer)
           (interprogram-cut-function nil)  ;; avoid clipboard interaction
           (interprogram-paste-function nil)
           (auto-capitalize-yank t))
      (kill-new (concat "testing bob." sep "testing sentence." sep "testing i’m.\ntesting newline\n"))
      (unwind-protect
          (ert-simulate-command '(yank))
        (should (equal (buffer-substring-no-properties (point-min) (point-max))
                       (concat "Testing bob." sep "Testing sentence." sep "Testing I’m.\nTesting newline\n")))
        (setq kill-ring old-kill-ring
              kill-ring-yank-pointer old-kill-ring-yank-pointer)))))

(ert-deftest auto-capitalize-text-after-abbreviations ()
  "Don’t capitalize after words in `auto-capitalize-abbrevs'."
  (auto-capitalize-tests--setup
   text-mode
   (dolist (abbrev auto-capitalize-abbrevs)
     (erase-buffer)
     (insert abbrev ?\s)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    (concat abbrev " a " ))))))

(ert-deftest auto-capitalize-text-after-quoted-abbreviations ()
  "Don’t capitalize after words in `auto-capitalize-abbrevs',
even if they appear inside quotes."
  (auto-capitalize-tests--setup
   text-mode
   (dolist (abbrev auto-capitalize-abbrevs)
     (erase-buffer)
     (insert "\"\"")
     (backward-char)
     (insert abbrev)
     (forward-char)
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    (concat "\"" abbrev "\" a " ))))

   (let ((sep (if sentence-end-double-space "  " " ")))
      (dolist (abbrev auto-capitalize-abbrevs)
        (erase-buffer)
        (insert "\"\".")
        (backward-char 2)
        (insert abbrev)
        (forward-char 2)
        (insert sep)
        (ert-simulate-command '(self-insert-command 1 ?a))
        (ert-simulate-command '(self-insert-command 1 ?\s))
        (should (equal (buffer-substring-no-properties (point-min) (point-max))
                       (concat "\"" abbrev "\"." sep "A ")))))))

(ert-deftest auto-capitalize-text-paragraph-indent-mode ()
  "Capitalize paragraphs in `paragraph-indent-minor-mode'."
  (auto-capitalize-tests--setup
   text-mode
   (paragraph-indent-minor-mode 1)
   (ert-simulate-command '(self-insert-command 1 ?\t))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  (concat "\tA " )))))

(ert-deftest auto-capitalize-text-fixed-case-with-triggers ()
  "Capitalize words in `auto-capitalize-fixed-case-words' after all members
of `auto-capitalize-trigger-chars'."
  (let ((cached auto-capitalize-fixed-case-words))
    (unwind-protect
        (auto-capitalize-tests--setup
         text-mode
         (setopt auto-capitalize-fixed-case-words '("I"))
         (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
         (insert "a")
         (ert-simulate-command '(self-insert-command 1 ?\s))

         (dolist (trigger auto-capitalize-trigger-chars)
           (ert-simulate-command '(self-insert-command 1 ?i))
           (ert-simulate-command `(self-insert-command 1 ,trigger))

           (should (equal (buffer-substring-no-properties (point-min) (point-max))
                          (concat "\nA I" (char-to-string trigger))))
           (backward-delete-char 2)))
      (setopt auto-capitalize-fixed-case-words cached))))


;;;; Tests for `tex-mode'

(ert-deftest auto-capitalize-tex-comments ()
  "Capitalize the first word in a `tex-mode' comment."
  (auto-capitalize-tests--setup
   tex-mode
   (ert-simulate-command '(self-insert-command 1 ?%))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "% A "))))

(ert-deftest auto-capitalize-tex-ignore-inline-% ()
  "Don't capitalize the first word after an inline (escaped) \"%\" in `tex-mode'."
  (auto-capitalize-tests--setup
   tex-mode
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?\\))
   (ert-simulate-command '(self-insert-command 1 ?%))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?b))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "A \\% b "))))

(ert-deftest auto-capitalize-tex-sections ()
  "Capitalize the first word in a `tex-mode' \\section{} title."
  (auto-capitalize-tests--setup
   tex-mode
   (insert "\\section{}")
   (backward-char)
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "\\section{A a }"))))

(ert-deftest auto-capitalize-tex-after-section-labels ()
  "Capitalize the first word in `tex-mode' after a \\label{} entry."
  (auto-capitalize-tests--setup
   tex-mode
   (insert "\\section{}\n")
   (insert "\\label{}\n")
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "\\section{}\n\\label{}\nA "))))

(ert-deftest auto-capitalize-tex-after-sections ()
  "Capitalize the first word after a `tex-mode' \\section{} title.

\\section serves as a proxy for all of `outline-regexp'."
  (auto-capitalize-tests--setup
   tex-mode
   (insert "\\section{}\n")
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "\\section{}\nA "))))

(ert-deftest auto-capitalize-tex-ignore-braceless-macro ()
  "Do not capitalize TeX macros."
  (auto-capitalize-tests--setup
   tex-mode
   (insert "\\bigskip")
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "\\bigskip "))))


;;;; Tests for `TeX-mode'

(ert-deftest auto-capitalize-TeX-math-dollar ()
  "Do not capitalize anything in `TeX-mode' $$ blocks."
  (skip-unless (featurep 'auctex))
  (auto-capitalize-tests--setup
   TeX-mode
   (when (fboundp #'electric-pair-mode)
     (electric-pair-local-mode -1))
   (ert-simulate-command '(self-insert-command 1 ?$))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "$a "))
   (erase-buffer)
   (ert-simulate-command '(self-insert-command 1 ?$))
   (ert-simulate-command '(self-insert-command 1 ?.))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "$. a "))
   (erase-buffer)
   (ert-simulate-command '(self-insert-command 1 ?$))
   (ert-simulate-command '(self-insert-command 1 ?i))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "$i "))))

(ert-deftest auto-capitalize-TeX-math-equation ()
  "Do not capitalize anything in `TeX-mode' \\equation env."
  (skip-unless (featurep 'auctex))
  (auto-capitalize-tests--setup
   TeX-mode
   (insert "\\begin{equation}\n\n\\end{equation}")
   (forward-line -1)
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "\\begin{equation}\na \n\\end{equation}"))
   (erase-buffer)
   (insert "\\begin{equation}\n\n\\end{equation}")
   (forward-line -1)
   (ert-simulate-command '(self-insert-command 1 ?.))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "\\begin{equation}\n. a \n\\end{equation}"))
   (erase-buffer)
   (insert "\\begin{equation}\n\n\\end{equation}")
   (forward-line -1)
   (ert-simulate-command '(self-insert-command 1 ?i))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "\\begin{equation}\ni \n\\end{equation}"))))

(ert-deftest auto-capitalize-TeX-whitelist-macros ()
  "Capitalize the first word in a `TeX-mode' whitelisted macro."
  (skip-unless (featurep 'auctex))
  (auto-capitalize-tests--setup
   TeX-mode
   (dolist (macro auto-capitalize-tex-macro-whitelist)
     (erase-buffer)
     (insert (concat "\\" macro "{}"))
     (backward-char)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    (concat "\\" macro "{A }" ))))))

(ert-deftest auto-capitalize-TeX-ignore-whitelist-macros ()
  "Don’t follow `TeX-mode' whitelisted macro if the context doesn't makesense."
  (skip-unless (featurep 'auctex))
  (auto-capitalize-tests--setup
   TeX-mode
   (dolist (macro auto-capitalize-tex-macro-whitelist)
     (erase-buffer)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (insert (concat "\\" macro "{}"))
     (backward-char)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    (concat "A \\" macro "{a }" ))))))


;;;; Tests for ‘org-mode’

(ert-deftest auto-capitalize-org-comments ()
  "Capitalize the first word in `org-mode' comments."
  (auto-capitalize-tests--setup
   org-mode
   (ert-simulate-command '(self-insert-command 1 ?#))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "# A "))))

(ert-deftest auto-capitalize-org-comment-sentence ()
  "Don't capitalize sentence starts in `org-mode' comments if
`auto-capitalize-comments' is nil."
  (auto-capitalize-tests--setup
   org-mode
   (let ((auto-capitalize-comments nil))
     (ert-simulate-command '(self-insert-command 1 ?#))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?.))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s)))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "# a. a "))))

(ert-deftest auto-capitalize-org-comments-non-first-line ()
  "Capitalize the first word of an org comment on a non-first line."
  (auto-capitalize-tests--setup
   org-mode
   (insert "Line\n")
   (ert-simulate-command '(self-insert-command 1 ?#))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "Line\n# A "))))

(ert-deftest auto-capitalize-org-ignore-inline-hash ()
  "Don't capitalize the first word after an inline `#' in `org-mode'."
  (auto-capitalize-tests--setup
   org-mode
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?#))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?b))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "A # b "))))

(ert-deftest auto-capitalize-org-headings-space ()
  "Capitalize the first word in `org-mode' headings after SPC."
  (auto-capitalize-tests--setup
   org-mode
   (ert-simulate-command '(self-insert-command 1 ?*))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-play-keys "SPC")
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "* A "))))

(ert-deftest auto-capitalize-org-headings-newline ()
  "Capitalize the first word in `org-mode' headings after RET."
  (auto-capitalize-tests--setup
   org-mode
   (ert-simulate-command '(self-insert-command 1 ?*))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-play-keys "RET")
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "* A\n"))))

(ert-deftest auto-capitalize-org-src-code ()
  "Don’t capitalize source code in `org-mode' src blocks."
  (auto-capitalize-tests--setup
    org-mode
    (insert "#+begin_src C\n\n#+end_src")
    (forward-line -1)
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-substring-no-properties (point-min) (point-max))
                   "#+begin_src C\na \n#+end_src"))))

(ert-deftest auto-capitalize-org-src-comments ()
  "Capitalize comments `org-mode' src blocks."
  (auto-capitalize-tests--setup
   org-mode
   (let ((org-src-content-indentation 0))
     (insert "#+begin_src C\n\n#+end_src")
     (forward-line -1)
     (ert-simulate-command '(comment-dwim 2))
     (font-lock-ensure)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    "#+begin_src C\n/* A  */\n#+end_src")))))

(ert-deftest auto-capitalize-org-src-comments-disabled ()
  "Don't capitalize comments in src blocks when `auto-capitalize-comments' is nil."
  (auto-capitalize-tests--setup
   org-mode
   (let ((org-src-content-indentation 0)
         (auto-capitalize-comments nil))
     (insert "#+begin_src C\n\n#+end_src")
     (forward-line -1)
     (ert-simulate-command '(comment-dwim 2))
     (font-lock-ensure)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    "#+begin_src C\n/* a  */\n#+end_src")))))

(ert-deftest auto-capitalize-org-src-strings ()
  "Capitalize strings `org-mode' src blocks."
  (auto-capitalize-tests--setup
   org-mode
   (let ((org-src-content-indentation 0))
     (insert "#+begin_src C\n\n#+end_src")
     (forward-line -1)
     (insert "\"\"")
     (backward-char)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
      (should (equal (buffer-string)
                     "#+begin_src C\n\"A \"\n#+end_src")))))

(ert-deftest auto-capitalize-org-src-strings-disabled ()
  "Don't capitalize strings in src blocks when `auto-capitalize-strings' is nil."
  (auto-capitalize-tests--setup
   org-mode
   (let ((org-src-content-indentation 0)
         (auto-capitalize-strings nil))
     (insert "#+begin_src C\n\n#+end_src")
     (forward-line -1)
     (insert "\"\"")
     (backward-char)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-string)
                    "#+begin_src C\n\"a \"\n#+end_src")))))


;;;; Tests for `prog-mode'
;; `emacs-lisp-mode' and `c-mode' are used as proxies

(ert-deftest auto-capitalize-prog-comments ()
  "Capitalize the first word in `prog-mode' comments.

Test both cases depending on the value of the user option
`auto-capitalize-comments'."
  (auto-capitalize-tests--setup
   emacs-lisp-mode
   (setq-local auto-capitalize-comments t)
   (ert-simulate-command '(comment-dwim 2))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  ";; A "))

   (erase-buffer)
   (setq-local auto-capitalize-comments nil)
   (ert-simulate-command '(comment-dwim 2))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  ";; a "))))

(ert-deftest auto-capitalize-prog-comments-newline ()
  "Capitalize the last word in a comment after a newline."
  (auto-capitalize-tests--setup
   emacs-lisp-mode
   (erase-buffer)
   (setq-local auto-capitalize-comments t)
   (ert-simulate-command '(comment-dwim 2))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(newline))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  ";; A\n"))))

(ert-deftest auto-capitalize-prog-strings ()
  "Capitalize the first word in `prog-mode' strings.

Test both cases depending on the value of the user option
`auto-capitalize-strings'."
  (auto-capitalize-tests--setup
   emacs-lisp-mode
   (setq-local auto-capitalize-strings t)
   (insert "\"\"")
   (backward-char)
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "\"A \""))

   (erase-buffer)
   (setq-local auto-capitalize-strings nil)
   (insert "\"\"")
   (backward-char)
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "\"a \""))))

(ert-deftest auto-capitalize-prog-ignore-bob ()
  "Don't capitalize the very first word in `prog-mode' buffers."
  (auto-capitalize-tests--setup
   c-mode
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "a "))))

(ert-deftest auto-capitalize-prog-defun-docstring ()
  "Capitalize the first word (and no other words) in `prog-mode' function
docstrings."
  (auto-capitalize-tests--setup
   emacs-lisp-mode
   (insert "(defun test-func ()")
   (ert-simulate-command '(newline))
   (insert "\"\"")
   (backward-char)
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "(defun test-func ()\n\"A a \""))))


(ert-deftest auto-capitalize-python-def-docstring ()
  "Capitalize the first word (and no other words) in `python-mode' function
docstrings."
  (auto-capitalize-tests--setup
   emacs-lisp-mode
   (insert "(def test-func ()")
   (ert-simulate-command '(newline))
   (insert "\"\"\"\"\"\"")
   (backward-char 3)
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "(def test-func ()\n\"\"\"A a \"\"\""))))

(ert-deftest auto-capitalize-prog-start-of-inline-strings ()
  "Test `auto-capitalize-start-of-inline-strings' off and on,
for both inline strings and newline-based (docstring) strings."
  (auto-capitalize-tests--setup
   emacs-lisp-mode
   (let ((auto-capitalize-strings t)
         (auto-capitalize-start-of-inline-strings nil))
     (insert "(setq x \"\")")
     (backward-char 2)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    "(setq x \"a \")")))

   ;; 2. Inline string, option on -> capitalized
   (erase-buffer)
   (let ((auto-capitalize-strings t)
         (auto-capitalize-start-of-inline-strings t))
     (insert "(setq x \"\")")
     (backward-char 2)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    "(setq x \"A \")")))

   ;; 3. Newline string, option off -> still capitalized (BOL check passes)
   (erase-buffer)
   (let ((auto-capitalize-strings t)
         (auto-capitalize-start-of-inline-strings nil))
     (insert "\"\"")
     (backward-char)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    "\"A \"")))

   ;; 4. Newline string, option on -> still capitalized
   (erase-buffer)
   (let ((auto-capitalize-strings t)
         (auto-capitalize-start-of-inline-strings t))
     (insert "\"\"")
     (backward-char)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    "\"A \"")))))

(ert-deftest auto-capitalize-prog-start-of-inline-comments ()
  "Test `auto-capitalize-start-of-inline-comments' off and on,
for both inline comments and newline-based (BOL) comments."
  (auto-capitalize-tests--setup
   emacs-lisp-mode
   ;; 1. Inline comment, option off -> not capitalized
   (let ((auto-capitalize-comments t)
         (auto-capitalize-start-of-inline-comments nil))
     (insert "(setq x 1)")
     (ert-simulate-command '(self-insert-command 1 ?\;))
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    "(setq x 1);a ")))

   ;; 2. Inline comment, option on -> capitalized
   (erase-buffer)
   (let ((auto-capitalize-comments t)
         (auto-capitalize-start-of-inline-comments t))
     (insert "(setq x 1)")
     (ert-simulate-command '(self-insert-command 1 ?\;))
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    "(setq x 1);A ")))

   ;; 3. BOL comment, option off -> still capitalized (BOL check passes)
   (erase-buffer)
   (let ((auto-capitalize-comments t)
         (auto-capitalize-start-of-inline-comments nil))
     (ert-simulate-command '(comment-dwim 2))
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    ";; A ")))

   ;; 4. BOL comment, option on -> still capitalized
   (erase-buffer)
   (let ((auto-capitalize-comments t)
         (auto-capitalize-start-of-inline-comments t))
     (ert-simulate-command '(comment-dwim 2))
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    ";; A ")))))

(ert-deftest auto-capitalize-text-fixed-case ()
  "Capitalize words in `auto-capitalize-fixed-case-words'."
  (let ((cached auto-capitalize-fixed-case-words))
    (unwind-protect
        (auto-capitalize-tests--setup
         emacs-lisp-mode
         (let ((auto-capitalize-comments t))
           (setopt auto-capitalize-fixed-case-words '("eMaCs"))
           (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
           (ert-simulate-command '(comment-dwim 2))
           (insert "emacs")
           (ert-simulate-command `(self-insert-command 1 ?\s))
           (should (equal (buffer-substring-no-properties (point-min) (point-max))
                          "\n;; eMaCs ")))
         (erase-buffer)
         (let ((auto-capitalize-strings t))
           (setopt auto-capitalize-fixed-case-words '("eMaCs"))
           (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
           (insert "\"\"")
           (backward-char)
           (insert "emacs")
           (ert-simulate-command `(self-insert-command 1 ?\s))
           (should (equal (buffer-substring-no-properties (point-min) (point-max))
                          "\n\"eMaCs \"")))
         (erase-buffer)
         (let ((auto-capitalize-strings t))
           (setopt auto-capitalize-fixed-case-words '("eMaCs" "Emacsen"))
           (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
           (insert "\"\"")
           (backward-char)
           (insert "emacsen")
           (ert-simulate-command `(self-insert-command 1 ?\s))
           (should (equal (buffer-substring-no-properties (point-min) (point-max))
                          "\n\"Emacsen \""))))
      (setopt auto-capitalize-fixed-case-words cached))))


;;;; Tests for `nxml-mode'

(ert-deftest auto-capitalize-nxml-comments ()
  "Capitalize the first word in `nxml-mode' comments."
  (auto-capitalize-tests--setup
   nxml-mode
   (ert-simulate-command '(comment-dwim 2))
   (font-lock-ensure)
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "<!--- A  --->"))

   (erase-buffer)
   (let ((auto-capitalize-comments nil))
     (ert-simulate-command '(comment-dwim 2))
     (font-lock-ensure)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    "<!--- a  --->")))))

(provide 'auto-capitalize-tests)
;;; auto-capitalize-tests.el ends here
