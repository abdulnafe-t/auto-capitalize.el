;;; auto-capitalize-org.el --- Org support for auto-capitalize.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Abdulnafé Toulaïmat

;; Author: Abdulnafé Toulaïmat <abdulnafe.toulaimat@gmail.com>
;; Assisted-by: OpenCode:Big_Pickle

;; Package-Requires: ((emacs "25.1")
;;                    (auto-capitalize "3.0")
;;                    (compat "31.0"))
;; Package-Version: 3.0
;; Keywords: text, convenience
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

;; This plugin adds Org support to `auto-capitalize'.

;;; Code:

(require 'auto-capitalize)

(declare-function org-in-src-block-p "org")
(declare-function org-at-comment-p "org")

(defgroup auto-capitalize-org nil
  "Org support for auto-capitalize."
  :group 'auto-capitalize)

(defun auto-capitalize-org-blocking-function ()
  "Block capitalization in org mode if appropriate.

Specifically, return non-nil to block capitalization if either:

1) Inside a src-block but not in comment a or a string

2) In a comment/string (either in src-blocks or not) and the
corresponding user option is nil

This predicate is added to `auto-capitalize-blocking-functions' (which
see)."
  (and (derived-mode-p 'org-mode)

       (or (not (nth 3 (syntax-ppss)))
           (not auto-capitalize-strings))

       (or (and (not (nth 4 (syntax-ppss)))
                (not (org-at-comment-p)))
           (not auto-capitalize-comments))

       (or (nth 3 (syntax-ppss))
           (nth 4 (syntax-ppss))
           (org-at-comment-p)
           (org-in-src-block-p))))

(defun auto-capitalize-org-trigger-function (_text-start word-start)
  "Trigger capitalization in `org-mode' buffers.

Returns non-nil if WORD-START should be capitalized based on
org-specific context that the default trigger function cannot handle.

This function checks if WORD-START is the first word of an org comment
\(lines starting with `#'), since org comments do not play nice with
`bounds-of-thing-at-point' or `start-of-paragraph-text'."
  (and (derived-mode-p 'org-mode)
       (org-at-comment-p)
       (= word-start
          (save-excursion
            (goto-char (line-beginning-position))
            (skip-syntax-forward "^w")
            (point)))))

;;;###autoload
(define-minor-mode auto-capitalize-org-mode
  "Toggle Org-specific capitalization support in this buffer.

When enabled, this mode adds Org-specific blocking and trigger
functions to `auto-capitalize-blocking-functions' and
`auto-capitalize-trigger-functions' buffer-locally.

If `auto-capitalize-mode' is not yet enabled in this buffer, it
will be enabled automatically."
  :lighter nil
  :group 'auto-capitalize-org
  (cond
   ((not auto-capitalize-org-mode)
    (remove-hook 'auto-capitalize-blocking-functions
                 #'auto-capitalize-org-blocking-function t)
    (remove-hook 'auto-capitalize-trigger-functions
                 #'auto-capitalize-org-trigger-function t))
   (t
    (unless (or auto-capitalize-mode auto-capitalize-global-mode)
      (auto-capitalize-mode 1)
      (message "auto-capitalize-mode enabled for Org support."))
    (add-hook 'auto-capitalize-blocking-functions
              #'auto-capitalize-org-blocking-function nil t)
    (add-hook 'auto-capitalize-trigger-functions
              #'auto-capitalize-org-trigger-function nil t))))

(provide 'auto-capitalize-org)
;;; auto-capitalize-org.el ends here
