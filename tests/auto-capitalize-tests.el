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


;;;; Tests for `text-mode'

(ert-deftest auto-capitalize-text-bob ()
  "Capitalize the first word in a text-mode buffer."
  (with-temp-buffer
    (text-mode)
    (auto-capitalize-mode 1)
    (goto-char (point-min))
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string) "A "))))

(ert-deftest auto-capitalize-text-triggers ()
  ;; FIXME: fails for ?. because of the i.e./e.g. exception
  "Capitalize the previous word after `auto-capitalize-trigger-chars'."
  :expected-result :failed
  (with-temp-buffer
    (text-mode)
    (auto-capitalize-mode 1)
    (ert-simulate-command '(newline))   ; Avoid repeating `auto-capitalize-bob'
    (dolist (trigger auto-capitalize-trigger-chars)
      (erase-buffer)
      (ert-simulate-command '(self-insert-command 1 ?a))
      (ert-simulate-command `(self-insert-command 1 ,trigger))
      (should (equal (buffer-string)
                     (concat "A" (char-to-string trigger)))))))


;;;; Tests for `tex-mode'

(ert-deftest auto-capitalize-tex-comments ()
  "Capitalize the first word in a comment in `tex-mode'."
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
  "Don't capitalize the first word after an inline `\\%' in `tex-mode'."
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
  "Capitalize the first word in a \\section{} title."
  (with-temp-buffer
    (tex-mode)
    (auto-capitalize-mode 1)
    (insert "\\section{}")
    (forward-char -1)
    (ert-simulate-command '(self-insert-command 1 ?a))
    (ert-simulate-command '(self-insert-command 1 ?\s))
    (should (equal (buffer-string)
                   "\\section{A }"))))


;;;; Tests for `emacs-lisp-mode'
;; `emacs-lisp-mode' is used as a proxy for `prog-mode'

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

(provide 'auto-capitalize-tests)
;;; auto-capitalize-tests.el ends here
