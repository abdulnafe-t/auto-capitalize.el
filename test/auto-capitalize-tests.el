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
(require 'auto-capitalize-sgml)
(require 'auto-capitalize-xml)
(when (featurep 'auctex)
  (require 'auto-capitalize-tex))

(defun auto-capitalize-tests--play-keys (keys)
  "Play KEYS as if typed by the user.
Inlines `ert-play-keys' (Emacs 31.1+) via `execute-kbd-macro'."
  (execute-kbd-macro (kbd keys)))

(defmacro auto-capitalize-tests--setup (mode &rest body)
  "Set up a buffer for auto-capitalize-tests."
  (declare (indent 1))
  `(ert-with-test-buffer
       (:name "*auto-capitalize-tests*")
     (,mode)
     (auto-capitalize-mode 1)
     (electric-quote-local-mode -1)
     (electric-pair-local-mode -1)
     (when (derived-mode-p 'TeX-mode)
       (auto-capitalize-tex-mode 1))
     (when (derived-mode-p 'org-mode)
       (auto-capitalize-org-mode 1))
     (when (derived-mode-p 'sgml-mode)
       (auto-capitalize-sgml-mode 1))
     (when (derived-mode-p 'nxml-mode)
       (auto-capitalize-xml-mode 1))
     (save-window-excursion
       (with-current-buffer (current-buffer)
         (with-selected-window (display-buffer (current-buffer))
           (progn ,@body))))))


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
  "Capitalize the previous word after non-word chars."
  (auto-capitalize-tests--setup
   text-mode
   (dolist (trigger '(?\s ?, ?. ?? ?' ?’ ?: ?\; ?- ?! ?\n))
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

(ert-deftest auto-capitalize-text-ie-mid-sentence ()
  "Don’t capitalize \"i.e.\" mid-sentence."
  (auto-capitalize-tests--setup
   text-mode
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?i))
   (ert-simulate-command '(self-insert-command 1 ?.))
   (ert-simulate-command '(self-insert-command 1 ?e))
   (ert-simulate-command '(self-insert-command 1 ?.))
   (ert-simulate-command '(self-insert-command 1 ?\s))

   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "A i.e. " ))))

(ert-deftest auto-capitalize-text-ie-sentence-start ()
  "Capitalize \"i.e.\" at the beginning of a sentence."
  :expected-result :failed
  (auto-capitalize-tests--setup
   text-mode
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?.))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?\s))

   (ert-simulate-command '(self-insert-command 1 ?i))
   (ert-simulate-command '(self-insert-command 1 ?.))
   (ert-simulate-command '(self-insert-command 1 ?e))
   (ert-simulate-command '(self-insert-command 1 ?.))
   (ert-simulate-command '(self-insert-command 1 ?\s))

   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "A.  I.e. " ))))

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

(ert-deftest auto-capitalize-text-fixed-case-after-abbreviations ()
  "Capitalize words in `auto-capitalize-fixed-case-words' after words in
`auto-capitalize-abbrevs' with a selection of non-word chars."
  (auto-capitalize-tests--setup
   text-mode
   (dolist (abbrev auto-capitalize-abbrevs)
     (dolist (trigger '(?\s ?, ?. ?? ?' ?’ ?: ?\; ?! ?\n))
       (erase-buffer)
       (insert abbrev ?\s)
       (ert-simulate-command '(self-insert-command 1 ?i))
       (ert-simulate-command `(self-insert-command 1 ,trigger))
       (should (equal (buffer-substring-no-properties (point-min) (point-max))
                      (concat abbrev " I" (char-to-string trigger))))))))

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
  "Capitalize words in `auto-capitalize-fixed-case-words' after non-word
chars."
  (let ((cached auto-capitalize-fixed-case-words))
    (unwind-protect
        (auto-capitalize-tests--setup
         text-mode
         (customize-set-variable 'auto-capitalize-fixed-case-words '("I"))
         (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
         (insert "a")
         (ert-simulate-command '(self-insert-command 1 ?\s))

         (dolist (trigger '(?\s ?, ?. ?? ?' ?’ ?: ?\; ?! ?\n))
           (ert-simulate-command '(self-insert-command 1 ?i))
           (ert-simulate-command `(self-insert-command 1 ,trigger))

           (should (equal (buffer-substring-no-properties (point-min) (point-max))
                          (concat "\nA I" (char-to-string trigger))))
           (backward-delete-char 2)))
      (customize-set-variable 'auto-capitalize-fixed-case-words cached))))


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


;;;; Tests for `TeX-mode'

(ert-deftest auto-capitalize-tex-ignore-braceless-macro ()
  "Do not capitalize TeX macros."
  (skip-unless (featurep 'auctex))
  (auto-capitalize-tests--setup
   tex-mode
   (insert "\\bigskip")
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "\\bigskip "))))

(ert-deftest auto-capitalize-TeX-math-dollar ()
  "Do not capitalize anything in `TeX-mode' $$ blocks."
  (skip-unless (featurep 'auctex))
  (auto-capitalize-tests--setup
   TeX-mode
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

(ert-deftest auto-capitalize-TeX-whitelist-macros-in-sentence ()
  "Capitalize the first word in a `TeX-mode' whitelisted macro at the start
of a sentence."
  (skip-unless (featurep 'auctex))
  (auto-capitalize-tests--setup
   TeX-mode
   (setq-local sentence-end-double-space nil)
   (dolist (macro auto-capitalize-tex-macro-whitelist)
     (erase-buffer)
     (insert "Some filler text. ")
     (insert (concat "\\" macro "{}"))
     (backward-char)
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    (concat "Some filler text. \\" macro "{A }" ))))))

(ert-deftest auto-capitalize-TeX-whitelist-macros-bol ()
  "Capitalize the first word in a `TeX-mode' whitelisted macro at BOL."
  (skip-unless (featurep 'auctex))
  (auto-capitalize-tests--setup
      TeX-mode
    (dolist (macro auto-capitalize-tex-macro-whitelist)
      (erase-buffer)
      (insert "\\begin{document}\n\n\\end{document}")
      (previous-line)
      (insert (concat "\\" macro "{}"))
      (backward-char)
      (ert-simulate-command '(self-insert-command 1 ?a))
      (ert-simulate-command '(self-insert-command 1 ?\s))
      (should (equal (buffer-substring-no-properties (point-min) (point-max))
                     (concat "\\begin{document}\n"
                             "\\" macro "{A }\n"
                             "\\end{document}"))))))

(ert-deftest auto-capitalize-TeX-ignore-whitelist-macros ()
  "Don’t follow `TeX-mode' whitelisted macro if the context doesn't make sense."
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
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "* A "))))

(ert-deftest auto-capitalize-org-headings-newline ()
  "Capitalize the first word in `org-mode' headings after RET."
  (auto-capitalize-tests--setup
   org-mode
   (ert-simulate-command '(self-insert-command 1 ?*))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(org-return))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "* A\n"))))

(ert-deftest auto-capitalize-org-headings-todo ()
  "Capitalize the first word in `org-mode' headings with a TODO keyword."
  (auto-capitalize-tests--setup
   org-mode
   (insert "* TODO ")
   (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-substring-no-properties (point-min) (point-max))
                   "* TODO A "))))

(ert-deftest auto-capitalize-org-headings-priority ()
  "Capitalize the first word in `org-mode' headings with a priority."
  (auto-capitalize-tests--setup
   org-mode
   (insert "* [#B] ")
   (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-substring-no-properties (point-min) (point-max))
                   "* [#B] A "))))

(ert-deftest auto-capitalize-org-headings-todo-priority ()
  "Capitalize the first word in `org-mode' headings with a TODO keyword and priority."
  (auto-capitalize-tests--setup
   org-mode
   (insert "* TODO [#A] ")
   (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-substring-no-properties (point-min) (point-max))
                   "* TODO [#A] A "))))

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
  "Capitalize comments in `org-mode' src blocks."
  (skip-unless (version<= "9.8" (org-version)))
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
  (skip-unless (version<= "9.8" (org-version)))
  (auto-capitalize-tests--setup
   org-mode
   (let ((org-src-content-indentation 0)
         (auto-capitalize-comments nil))
     (insert "#+begin_src C\n\n#+end_src")
     (forward-line -1)
     (ert-simulate-command '(comment-dwim 2))
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    "#+begin_src C\n/* a  */\n#+end_src")))))

(ert-deftest auto-capitalize-org-src-strings ()
  "Capitalize strings in `org-mode' src blocks."
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
   (insert "(defun test_func ()")
   (ert-simulate-command '(newline))
   (insert "\"\"")
   (backward-char)
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "(defun test_func ()\n\"A a \""))))

(ert-deftest auto-capitalize-prog-fixed-case ()
  "Capitalize words in `auto-capitalize-fixed-case-words'."
  (let ((cached auto-capitalize-fixed-case-words))
    (unwind-protect
        (auto-capitalize-tests--setup
         emacs-lisp-mode
         (let ((auto-capitalize-comments t))
           (customize-set-variable 'auto-capitalize-fixed-case-words '("eMaCs"))
           (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
           (ert-simulate-command '(comment-dwim 2))
           (insert "emacs")
           (ert-simulate-command `(self-insert-command 1 ?\s))
           (should (equal (buffer-substring-no-properties (point-min) (point-max))
                          "\n;; eMaCs ")))
         (erase-buffer)
         (let ((auto-capitalize-strings t))
           (customize-set-variable 'auto-capitalize-fixed-case-words '("eMaCs"))
           (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
           (insert "\"\"")
           (backward-char)
           (insert "emacs")
           (ert-simulate-command `(self-insert-command 1 ?\s))
           (should (equal (buffer-substring-no-properties (point-min) (point-max))
                          "\n\"eMaCs \"")))
         (erase-buffer)
         (let ((auto-capitalize-strings t))
           (customize-set-variable 'auto-capitalize-fixed-case-words '("eMaCs" "Emacsen"))
           (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
           (insert "\"\"")
           (backward-char)
           (insert "emacsen")
           (ert-simulate-command `(self-insert-command 1 ?\s))
           (should (equal (buffer-substring-no-properties (point-min) (point-max))
                          "\n\"Emacsen \""))))
      (customize-set-variable 'auto-capitalize-fixed-case-words cached))))

(ert-deftest auto-capitalize-python-def-docstring ()
  "Capitalize the first word (and no other words) in `python-mode' function
docstrings."
  (auto-capitalize-tests--setup
   python-mode
   (insert "def test_func:")
   (ert-simulate-command '(newline))
   (insert "\"\"\"\"\"\"")
   (backward-char 3)
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "def test_func:\n\"\"\"A a \"\"\""))))

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


;;;; Tests for `nxml-mode'

(ert-deftest auto-capitalize-nxml-comments ()
  "Capitalize the first word in `nxml-mode' comments."
  (auto-capitalize-tests--setup
   nxml-mode
   (ert-simulate-command '(comment-dwim 2))
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "<!--- A  --->"))

   (erase-buffer)
   (let ((auto-capitalize-comments nil))
     (ert-simulate-command '(comment-dwim 2))
     (ert-simulate-command '(self-insert-command 1 ?a))
     (ert-simulate-command '(self-insert-command 1 ?\s))
     (should (equal (buffer-substring-no-properties (point-min) (point-max))
                    "<!--- a  --->")))))

(ert-deftest auto-capitalize-nxml-data ()
  "Capitalize data in XML."
  (auto-capitalize-tests--setup
   nxml-mode
   (insert "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<tag></tag>")
   (search-backward "<tag>")
   (forward-char 5)
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<tag>A </tag>"))))


;;;; Tests for `sgml-mode'

(ert-deftest auto-capitalize-html-body ()
  "Capitalize HTML body text."
  (auto-capitalize-tests--setup
   html-mode
   (insert "<html>\n<body>\n\n</body>\n</html>")
   (search-backward "<body>\n")
   (forward-char 7)
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "<html>\n<body>\nA \n</body>\n</html>"))))

(ert-deftest auto-capitalize-html-tags ()
  "Don't capitalize HTML tags."
  (auto-capitalize-tests--setup
   html-mode
   (insert "<html>\n\n</html>")
   (search-backward "<html>\n")
   (forward-char 7)
   (ert-simulate-command '(self-insert-command 1 ?<))
   (ert-simulate-command '(self-insert-command 1 ?p))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "<html>\n<p \n</html>"))))


;;;; Tests for treesitter-modes

(defun auto-capitalize-tests--ts-grammar-available-p (lang)
  "Return non-nil if the tree-sitter grammar for LANG is available.
Returns nil when the current Emacs predates the tree-sitter API."
  (and (fboundp 'treesit-language-available-p)
       (treesit-language-available-p lang)))

(ert-deftest auto-capitalize-mhtml-ts-comments ()
  "Capitalize the first word in embedded `mhtml-ts-mode' JavaScript
comments."
  ;; `mhtml-ts-mode' requires the `html', `javascript', `css' and
  ;; `jsdoc' grammars.
  (skip-unless (and (fboundp 'mhtml-ts-mode)
                    (auto-capitalize-tests--ts-grammar-available-p 'html)
                    (auto-capitalize-tests--ts-grammar-available-p 'javascript)
                    (auto-capitalize-tests--ts-grammar-available-p 'css)
                    (auto-capitalize-tests--ts-grammar-available-p 'jsdoc)))
  (auto-capitalize-tests--setup
   mhtml-ts-mode
   (insert "<script>\nlet x; // \n</script>")
   (search-backward "// ")
   (forward-char 3)
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "<script>\nlet x; // A \n</script>"))))

(ert-deftest auto-capitalize-mhtml-ts-embedded-code ()
  "Don't capitalize embedded code."
  ;; `mhtml-ts-mode' requires the `html', `javascript', `css' and
  ;; `jsdoc' grammars.
  (skip-unless (and (fboundp 'mhtml-ts-mode)
                    (auto-capitalize-tests--ts-grammar-available-p 'html)
                    (auto-capitalize-tests--ts-grammar-available-p 'javascript)
                    (auto-capitalize-tests--ts-grammar-available-p 'css)
                    (auto-capitalize-tests--ts-grammar-available-p 'jsdoc)))
  (auto-capitalize-tests--setup
   mhtml-ts-mode
   (insert "<script>\n\n</script>")
   (search-backward "\n")
   (ert-simulate-command '(self-insert-command 1 ?a))
   (ert-simulate-command '(self-insert-command 1 ?\s))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "<script>\na \n</script>"))))

;;;; Undo

(ert-deftest auto-capitalize-undo-cap-dont-move-point ()
  "Make sure undoing capitalization does not move point."
  (auto-capitalize-tests--setup
   emacs-lisp-mode
   (auto-capitalize-tests--play-keys "M-;")
   (auto-capitalize-tests--play-keys "a")
   (auto-capitalize-tests--play-keys "SPC")
   (auto-capitalize-tests--play-keys "C-x u")
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  ";; a "))
   (should (equal (point) (point-max)))))

(ert-deftest auto-capitalize-undo-ie-dont-move-point ()
  "Make sure undoing capitalization does not move point."
  (auto-capitalize-tests--setup
   emacs-lisp-mode
   (auto-capitalize-tests--play-keys "M-;")
   (auto-capitalize-tests--play-keys "i.e.")
   (auto-capitalize-tests--play-keys "C-x u")
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  ";; I.e."))
   (should (equal (point) (point-max)))))

(ert-deftest auto-capitalize-undo-fixed-case-dont-move-point ()
  "Make sure undoing capitalization does not move point."
  (auto-capitalize-tests--setup
   emacs-lisp-mode
   (auto-capitalize-tests--play-keys "M-;")
   (auto-capitalize-tests--play-keys "you SPC and SPC i SPC")
   (auto-capitalize-tests--play-keys "C-x u")
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  ";; You and i "))
   (should (equal (point) (point-max)))))

;;;; Misc.

(ert-deftest auto-capitalize-global-modes-test ()
  "Don't activate `auto-capitalize-mode' in any major mode excluded in
`auto-capitalize-global-modes'."
  (auto-capitalize-global-mode)
  (ert-with-test-buffer
      (:name "*Auto-capitalize-test-buffer*")
    (dolist (mode (cdar auto-capitalize-global-modes))
      (when (fboundp mode)
        (funcall mode)
        (should-not auto-capitalize-mode)))))

(ert-deftest auto-capitalize-temp-buffers ()
  "Don't activate `auto-capitalize-mode' in any temp buffer."
  (auto-capitalize-global-mode)
  (with-temp-buffer
    (emacs-lisp-mode)
    (should-not auto-capitalize-mode))

  (with-temp-buffer
    (lisp-data-mode)
    (should-not auto-capitalize-mode)))

(ert-deftest auto-capitalize-scratch-buffer ()
  "Make sure `auto-capitalize-mode' works in *scratch*."
  (auto-capitalize-global-mode)
  (setq inhibit-splash-screen t)
  (with-current-buffer "*scratch*"
    (should auto-capitalize-mode)
    (ert-simulate-command '(comment-dwim 2))
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-substring-no-properties (point-min) (point-max))
                   ";; A "))))

(ert-deftest auto-capitalize-file-paths ()
  "Don't capitalize filepaths."
  (auto-capitalize-tests--setup
   text-mode
   (insert "/")
   (insert "home")
   (ert-simulate-command '(self-insert-command 1 ?/))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "/home/"))))

(ert-deftest auto-capitalize-uri ()
  "Don't capitalize URI schemes."
  (auto-capitalize-tests--setup
   text-mode
   (insert "https")
   (ert-simulate-command '(self-insert-command 1 ?:))
   (should (equal (buffer-substring-no-properties (point-min) (point-max))
                  "https:"))))

(provide 'auto-capitalize-tests)
;;; auto-capitalize-tests.el ends here
