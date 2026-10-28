;;; auto-capitalize-xml.el --- XML plugin for auto-capitalize.el.  -*- lexical-binding: t; -*-

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

;; This plugin adds XML support to `auto-capitalize' via `nxml-mode'.

;;; Code:

(require 'auto-capitalize)

(declare-function nxml-get-inside "nxml-rap")

(defgroup auto-capitalize-xml
  nil
  "Customization group for auto-capitalize-xml."
  :group 'auto-capitalize)

(defun auto-capitalize-xml-blocking-function (_text-start word-start)
  "Block if the word at WORD-START is not in text, a comment, or a string."
  (not (nxml-get-inside word-start)))

(defvar auto-capitalize-xml--lighter "/XML"
  "Appended to `auto-capitalize--lighter' by `auto-capitalize-xml-mode'.")

;;;###autoload
(define-minor-mode auto-capitalize-xml-mode
  "Toggle XML-specific capitalization support in this buffer.

When enabled, this mode adds `auto-capitalize-xml-blocking-function' to
`auto-capitalize-blocking-functions', and `auto-capitalize-xml-trigger-function'
to `auto-capitalize-trigger-functions' buffer-locally.

If `auto-capitalize-mode' is not yet enabled in this buffer, it
will be enabled automatically."
  :lighter nil
  (cond
   ((not auto-capitalize-xml-mode)
    (remove-hook 'auto-capitalize-blocking-functions
                 #'auto-capitalize-xml-blocking-function t)
    (setq-local auto-capitalize--lighter
                (string-replace
                 auto-capitalize-xml--lighter
                 ""
                 auto-capitalize--lighter)))

   (t
    (unless auto-capitalize-mode
      (auto-capitalize-mode 1)
      (message "auto-capitalize-mode enabled for XML support."))
    (add-hook 'auto-capitalize-blocking-functions
              #'auto-capitalize-xml-blocking-function nil t)

    (setq-local auto-capitalize--lighter
                (concat auto-capitalize--lighter
                        auto-capitalize-xml--lighter)))))

(provide 'auto-capitalize-xml)
;;; auto-capitalize-xml.el ends here
