;;; auto-capitalize-sgml.el --- SGML plugin for auto-capitalize.el.  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Abdulnafé Toulaïmat

;; Author: Abdulnafé Toulaïmat <abdulnafe.toulaimat@gmail.com>
;; Keywords: text, wp, convenience

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

;; This plugin adds SGML support to `auto-capitalize'. This includes modes such
;; as `html-mode', `html-ts-mode', and `mhtml-ts-mode'.

;;; Code:

(require 'auto-capitalize)

(declare-function sgml-lexical-context "sgml-mode")

(defgroup auto-capitalize-sgml
  nil
  "Customization group for auto-capitalize-sgml."
  :group 'auto-capitalize)

(defun auto-capitalize-sgml-blocking-function (_text-start word-start)
  "Block if the word at WORD-START is not in text, a comment, or a string."
  (save-excursion
    (goto-char word-start)
    (or
     (not (memq (car (sgml-lexical-context))
                '(text comment string)))
     (auto-capitalize--treesit-embedded-p '(javascript css)))))

(defvar auto-capitalize-sgml--lighter "/SGML"
  "Appended to `auto-capitalize--lighter' by `auto-capitalize-sgml-mode'.")

;;;###autoload
(define-minor-mode auto-capitalize-sgml-mode
  "Toggle SGML-specific capitalization support in this buffer.

When enabled, this mode adds `auto-capitalize-sgml-blocking-function' to
`auto-capitalize-blocking-functions' buffer-locally.

If `auto-capitalize-mode' is not yet enabled in this buffer, it
will be enabled automatically."
  :lighter nil
  (cond
   ((not auto-capitalize-sgml-mode)
    (remove-hook 'auto-capitalize-blocking-functions
                 #'auto-capitalize-sgml-blocking-function t)
    (setq-local auto-capitalize--lighter
                (string-replace
                 auto-capitalize-sgml--lighter
                 ""
                 auto-capitalize--lighter)))

   (t
    (unless auto-capitalize-mode
      (auto-capitalize-mode 1)
      (message "auto-capitalize-mode enabled for SGML (%s) support."
               (replace-regexp-in-string "\\(-ts\\)?-mode" ""
                                         (symbol-name major-mode))))
    (add-hook 'auto-capitalize-blocking-functions
              #'auto-capitalize-sgml-blocking-function nil t)

    (setq-local auto-capitalize--lighter
                (concat auto-capitalize--lighter
                        auto-capitalize-sgml--lighter)))))

(provide 'auto-capitalize-sgml)
;;; auto-capitalize-sgml.el ends here
