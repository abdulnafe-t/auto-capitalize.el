;;; auto-capitalize-tex.el --- TeX plugin for auto-capitalize.el  -*- lexical-binding: t; -*-

;; Copyright   2026 Abdulnafé Toulaïmat

;; Author: Abdulnafé Toulaïmat <abdulnafe.toulaimat@gmail.com>
;; Assisted-by: OpenCode:Big_Pickle

;; Package-Requires: ((emacs "25.1")
;;                    (auto-capitalize "3.0")
;;                    (auctex "11.82")
;;                    (compat "31.0"))
;;
;; Package-Version: 3.0
;; Keywords: tex, wp, convenience
;; URL: https://github.com/abdulnafe-t/auto-capitalize-el

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

;; This plugin adds TeX support to `auto-capitalize'. It requires `AUCTeX'.

;;; Code:

(require 'auto-capitalize)

(declare-function texmathp "ext:texmathp")
(declare-function TeX-current-macro "ext:tex")
(declare-function TeX-escaped-p "ext:tex")
(declare-function TeX-mode-p "ext:tex")
(declare-function TeX-find-macro-start "ext:tex")

(defgroup auto-capitalize-tex nil
  "TeX support for auto-capitalize."
  :group 'auto-capitalize)

(defcustom auto-capitalize-tex-macro-whitelist
  '("intertext" "text" "textbf" "textit" "textsl" "textsc" "textrm" "textsf" "texttt"
    "textup" "textmd" "emph" "underline" "textnormal"
    "title" "author" "date" "thanks" "caption"
    "textsuperscript" "textsubscript"
    ;; beamer
    "frametitle" "framesubtitle" "institute" "subtitle"
    ;; soul
    "ul" "st" "hl" "caps" "so"
    ;; ulem
    "uline" "uuline" "uwave" "sout" "xout" "dashuline" "dotuline"
    ;; xcolor
    "textcolor" "colorbox" "fcolorbox")

  "List of TeX macros whose first argument should have its first word capitalized.
Only macros taking plain text as an argument should be included. Macros
matching `outline-regexp' (like \\section) need not be listed, as they
are already handled by the outline-heading check in
`auto-capitalize-default-trigger-function'."
  :group 'auto-capitalize-tex
  :type '(repeat (string :tag "Macro name")))

(defun auto-capitalize-tex-blocking-function ()
  "Block capitalization in TeX math environment, detected with `texmathp'.

This predicate is added to `auto-capitalize-blocking-functions'."
  (and (bound-and-true-p TeX-mode-p)
       (save-excursion
         (or (progn
               (backward-word)
               (TeX-escaped-p))
             (texmathp)))))

(defun auto-capitalize-tex-trigger-function (_text-start word-start)
  "Return non-nil if capitalization should occur at WORD-START.

TEXT-START is ignored; the check uses WORD-START and the buffer content
before it. Specifically, this function returns non-nil if WORD-START
follows the opening brace of a whitelisted TeX macro, i.e. one that's a
member of `auto-capitalize-tex-macro-whitelist', AND the macro itself
sits at a standard capitalization boundary (paragraph start, sentence
start, etc.).

This function is added to `auto-capitalize-trigger-functions'."
  (when-let* ((_ (bound-and-true-p TeX-mode-p))
              (macro (TeX-current-macro))
              (_ (member macro auto-capitalize-tex-macro-whitelist))
              (macro-start
               (save-excursion
                 (goto-char word-start)
                 (skip-syntax-backward " ")
                 (when (and (eq (char-before) ?{)
                            (not (TeX-escaped-p (1- (point)))))
                   (TeX-find-macro-start)))))
    (auto-capitalize-default-trigger-function
     (1- macro-start) macro-start)))

;;;###autoload
(define-minor-mode auto-capitalize-tex-mode
  "Toggle TeX-specific capitalization support in this buffer.

When enabled, this mode adds TeX-specific blocking and trigger
functions to `auto-capitalize-blocking-functions' and
`auto-capitalize-trigger-functions' buffer-locally.

Note that this mode requires `AUCTeX'.

If `auto-capitalize-mode' is not yet enabled in this buffer, it
will be enabled automatically."
  :lighter nil
  :group 'auto-capitalize-tex
  (cond
   ((not auto-capitalize-tex-mode)
    (remove-hook 'auto-capitalize-blocking-functions
                 #'auto-capitalize-tex-blocking-function t)
    (remove-hook 'auto-capitalize-trigger-functions
                 #'auto-capitalize-tex-trigger-function t))

   (t
    (unless auto-capitalize-mode
      (auto-capitalize-mode 1)
      (message "auto-capitalize-mode enabled for TeX support."))
    (add-hook 'auto-capitalize-blocking-functions
              #'auto-capitalize-tex-blocking-function nil t)
    (add-hook 'auto-capitalize-trigger-functions
              #'auto-capitalize-tex-trigger-function nil t))))

(provide 'auto-capitalize-tex)
;;; auto-capitalize-tex.el ends here
