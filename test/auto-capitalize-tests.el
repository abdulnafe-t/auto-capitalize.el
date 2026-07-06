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
(when (featurep 'auctex)
  (require 'auto-capitalize-tex))


;;;; Tests for `text-mode'

(ert-deftest auto-capitalize-text-bob ()
  "Capitalize the first word in a `text-mode' buffer."
  (with-temp-buffer
    (text-mode)
    (auto-capitalize-mode 1)
    (goto-char (point-min))
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string) "A "))))

(ert-deftest auto-capitalize-text-triggers ()
  "Capitalize the previous word after `auto-capitalize-trigger-chars'."
  (with-temp-buffer
    (text-mode)
    (auto-capitalize-mode 1)
    (dolist (trigger auto-capitalize-trigger-chars)
      (erase-buffer)
      (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
      (ert-simulate-command '(self-insert-command 1 ?a))
      (ert-simulate-command `(self-insert-command 1 ,trigger))
      (should (equal (buffer-string)
                     (concat "\nA" (char-to-string trigger)))))))

(ert-deftest auto-capitalize-text-yank ()
  "Capitalize yanked text."
  (with-temp-buffer
    (text-mode)
    (auto-capitalize-mode 1)
    (let ((old-kill-ring kill-ring)
          (old-kill-ring-yank-pointer kill-ring-yank-pointer)
          (interprogram-cut-function nil)  ;; avoid clipboard interaction
          (interprogram-paste-function nil)
          (auto-capitalize-yank t))
      (kill-new "testing bob. testing sentence. testing i’m.\ntesting newline")
      (unwind-protect
          (ert-simulate-command '(yank))
        (should (equal (buffer-string)
                       (concat "Testing bob. Testing sentence. Testing I’m.\nTesting newline")))
        (setq kill-ring old-kill-ring
              kill-ring-yank-pointer old-kill-ring-yank-pointer)))))


;;;; Tests for `tex-mode'

(ert-deftest auto-capitalize-tex-comments ()
  "Capitalize the first word in a `tex-mode' comment."
  (with-temp-buffer
    (tex-mode)
    (auto-capitalize-mode 1)
    (ert-simulate-command '(self-insert-command 1 ?%))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "% A "))))

(ert-deftest auto-capitalize-tex-ignore-inline-% ()
  "Don't capitalize the first word after an inline (escaped) `%' in `tex-mode'."
  (with-temp-buffer
    (tex-mode)
    (auto-capitalize-mode 1)
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (ert-simulate-command '(self-insert-command 1 ?\\))
    (ert-simulate-command '(self-insert-command 1 ?%))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (ert-simulate-command '(self-insert-command 1 ?b))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "A \\% b "))))

(ert-deftest auto-capitalize-tex-sections ()
  "Capitalize the first word in a `tex-mode' \\section{} title."
  (with-temp-buffer
    (tex-mode)
    (auto-capitalize-mode 1)
    (insert "\\section{}")
    (backward-char)
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "\\section{A }"))))


;;;; Tests for `TeX-mode'

(ert-deftest auto-capitalize-TeX-math-dollar ()
  "Do not capitalize anything in `TeX-mode' $$ blocks."
  (skip-unless (featurep 'auctex))
  (with-temp-buffer
    (TeX-mode)
    (auto-capitalize-mode 1)
    (when (fboundp #'electric-pair-mode)
      (electric-pair-local-mode -1))
    (ert-simulate-command '(self-insert-command 1 ?$))
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "$a "))
    (erase-buffer)
    (ert-simulate-command '(self-insert-command 1 ?$))
    (ert-simulate-command '(self-insert-command 1 ?.))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "$. a "))
    (erase-buffer)
    (ert-simulate-command '(self-insert-command 1 ?$))
    (ert-simulate-command '(self-insert-command 1 ?i))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "$i "))))

(ert-deftest auto-capitalize-TeX-math-equation ()
  "Do not capitalize anything in `TeX-mode' \equation{} env."
  (skip-unless (featurep 'auctex))
  (with-temp-buffer
    (TeX-mode)
    (auto-capitalize-mode 1)
    (insert "\\begin{equation}\n\n\\end{equation}")
    (forward-line -1)
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "\\begin{equation}\na \n\\end{equation}"))
    (erase-buffer)
    (insert "\\begin{equation}\n\n\\end{equation}")
    (forward-line -1)
    (ert-simulate-command '(self-insert-command 1 ?.))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "\\begin{equation}\n. a \n\\end{equation}"))
    (erase-buffer)
    (insert "\\begin{equation}\n\n\\end{equation}")
    (forward-line -1)
    (ert-simulate-command '(self-insert-command 1 ?i))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "\\begin{equation}\ni \n\\end{equation}"))))

(ert-deftest auto-capitalize-TeX-whitelist-macros ()
  "Capitalize the first word in a `TeX-mode' whitelisted macro."
  (skip-unless (featurep 'auctex))
  (with-temp-buffer
    (TeX-mode)
    (auto-capitalize-mode 1)
    (dolist (macro auto-capitalize-tex-macro-whitelist)
      (erase-buffer)
      (insert (concat "\\" macro "{}"))
      (backward-char)
      (ert-simulate-command '(self-insert-command 1 ?a))
      (ert-simulate-command '(self-insert-command 1 ?\s))
      (should (equal (buffer-string)
                     (concat "\\" macro "{A }" ))))))

(ert-deftest auto-capitalize-TeX-ignore-whitelist-macros ()
  "Don’t capitalize the first word in a `TeX-mode' whitelisted macro if the
context doesn’t make sense."
  (skip-unless (featurep 'auctex))
  (with-temp-buffer
    (TeX-mode)
    (auto-capitalize-mode 1)
    (dolist (macro auto-capitalize-tex-macro-whitelist)
      (erase-buffer)
      (ert-simulate-command '(self-insert-command 1 ?a))
      (ert-simulate-command '(self-insert-command 1 ?\s))
      (insert (concat "\\" macro "{}"))
      (backward-char)
      (ert-simulate-command '(self-insert-command 1 ?a))
      (ert-simulate-command '(self-insert-command 1 ?\s))
      (should (equal (buffer-string)
                     (concat "A \\" macro "{a }" ))))))


;;;; Tests for ‘org-mode’

(ert-deftest auto-capitalize-org-comments ()
  "Capitalize the first word in `org-mode' comments."
  (with-temp-buffer
    (org-mode)
    (auto-capitalize-mode 1)
    (ert-simulate-command '(self-insert-command 1 ?#))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "# A "))))

(ert-deftest auto-capitalize-org-ignore-inline-hash ()
  "Don't capitalize the first word after an inline `#' in `org-mode'."
  (with-temp-buffer
    (org-mode)
    (auto-capitalize-mode 1)
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (ert-simulate-command '(self-insert-command 1 ?#))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (ert-simulate-command '(self-insert-command 1 ?b))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "A # b "))))

(ert-deftest auto-capitalize-org-headings ()
  "Capitalize the first word in `org-mode' headings."
  (with-temp-buffer
    (org-mode)
    (auto-capitalize-mode 1)
    (ert-simulate-command '(self-insert-command 1 ?*))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "* A "))))


;;;; Tests for `prog-mode'
;; `emacs-lisp-mode' and `c-mode' are used as proxies

(ert-deftest auto-capitalize-prog-comments ()
  "Capitalize the first word in `prog-mode' comments.

Test both cases depending on the value of the user option
`auto-capitalize-comments'."
  (with-temp-buffer
    (emacs-lisp-mode)
    (auto-capitalize-mode 1)
    (setq-local auto-capitalize-comments t)
    (ert-simulate-command '(comment-dwim 2))
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   ";; A "))

    (erase-buffer)
    (setq-local auto-capitalize-comments nil)
    (ert-simulate-command '(comment-dwim 2))
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   ";; a "))))

(ert-deftest auto-capitalize-prog-strings ()
  "Capitalize the first word in `prog-mode' strings.

Test both cases depending on the value of the user option
`auto-capitalize-strings'."
  (with-temp-buffer
    (emacs-lisp-mode)
    (auto-capitalize-mode 1)
    (setq-local auto-capitalize-strings t)
    (insert "\"\"")
    (backward-char)
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "\"A \""))

    (erase-buffer)
    (setq-local auto-capitalize-strings nil)
    (insert "\"\"")
    (backward-char)
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "\"a \""))))

(ert-deftest auto-capitalize-prog-ignore-bob ()
  "Don't capitalize the very first word in `prog-mode' buffers."
  (with-temp-buffer
    (c-mode)
    (auto-capitalize-mode 1)
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "a "))))

(ert-deftest auto-capitalize-text-fixed-case ()
  "Capitalize words in `auto-capitalize-fixed-case-words'."
  (with-temp-buffer
    (emacs-lisp-mode)
    (auto-capitalize-mode 1)
    (let ((auto-capitalize-fixed-case-words '("eMaCs"))
          (auto-capitalize-comments nil))
      (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
      (ert-simulate-command '(comment-dwim 2))
      (insert "emacs")
      (ert-simulate-command `(self-insert-command 1 ?\s))
      (should (equal (buffer-string)
                     "\n;; eMaCs ")))
    (erase-buffer)
    (let ((auto-capitalize-fixed-case-words '("eMaCs"))
          (auto-capitalize-strings nil))
      (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
      (insert "\"\"")
      (backward-char)
      (insert "emacs")
      (ert-simulate-command `(self-insert-command 1 ?\s))
      (should (equal (buffer-string)
                     "\n\"eMaCs \"")))
    (erase-buffer)
    (let ((auto-capitalize-fixed-case-words '("eMaCs" "Emacsen"))
          (auto-capitalize-strings nil))
      (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
      (insert "\"\"")
      (backward-char)
      (insert "emacsen")
      (ert-simulate-command `(self-insert-command 1 ?\s))
      (should (equal (buffer-string)
                     "\n\"Emacsen \"")))))

(provide 'auto-capitalize-tests)
;;; auto-capitalize-tests.el ends here
