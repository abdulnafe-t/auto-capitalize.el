;;; auto-capitalize.el --- Automatically capitalize (or upcase) words -*- lexical-binding: t; -*-

;; Copyright   1998,2001,2002,2005 Kevin Rodgers
;; Copyright   2026 Abdulnafé Toulaïmat

;; Original Author: Kevin Rodgers <ihs_4664@yahoo.com>
;; (Please don’t contact original author if you found a bug in this
;; package)
;; Past maintainer: Yuta Yamada <cokesboy at gmail.com>
;; Maintainer: Abdulnafé Toulaïmat <abdulnafe.toulaimat@gmail.com>
;; Assisted-by: OpenCode:Big_Pickle
;; Package-Requires: ((emacs "25.1")
;;                    (compat "31.0"))

;; Created: 20 May 1998
;; Package-Version: 3.0
;; Keywords: text, wp, convenience
;; URL: https://github.com/abdulnafe-t/auto-capitalize-el

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be
;; useful, but WITHOUT ANY WARRANTY; without even the implied
;; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
;; PURPOSE.  See the GNU General Public License for more details.

;; You should have received a copy of the GNU General Public
;; License along with this program; if not, write to the Free
;; Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
;; MA 02111-1307 USA

;;; Commentary:

;; `auto-capitalize-mode' is a minor mode that automatically capitalizes text as
;; you type. It does this at the start of sentences/paragraphs, as well as in
;; comments or strings in any `prog-mode' buffer, or indeed any buffer where
;; comments are defined by the major mode (Org, TeX,...).
;;
;; The heart of the package is `auto-capitalize-capitalize', which is installed
;; in `after-change-functions' when the mode is enabled. It serves as the main
;; entry point for the capitalization logic, which is based on two hooks that
;; you can add your own predicates to. The `auto-capitalize-blocking-functions'
;; hook gives you the right of first refusal over capitalization: each function
;; in that hook is called with no arguments and returns nil to block
;; capitalization. If any function returns nil, the check fails and no word is
;; capitalized. Note, however, that even if every function in this hook returns
;; non-nil, that does not guarantee a word will be capitalized.
;;
;; By default, this hook only contains
;; `auto-capitalize-default-blocking-function' and
;; `auto-capitalize-org-blocking-function'. Additional plugins, like the
;; provided `auto-capitalize-tex', can add their own predicates.
;;
;; The second hook is `auto-capitalize-trigger-functions'. These functions are
;; called with the starting positions of both the current text and the current
;; word, and if any of them returns non-nil, capitalization occurs.
;;
;; Note that the blocking functions take precedence: they are called first, and
;; only if they all return non-nil, the trigger functions get called.
;;
;; Alternatively, if you do not want to write a whole new predicate, you can
;; always customize some of the user options in the `auto-capitalize' group.
;; Examples include `auto-capitalize-strings', which controls whether strings in
;; prog-mode should be auto-capitalized, and its comment analogue
;; `auto-capitalize-comments'.
;;
;; This package is a revamp of Yuta Yamada’s version
;; (https://github.com/yuutayamada/auto-capitalize-el), which is itself a fork
;; of the original auto-capitalize.el, written by Kevin Rodgers and shared on
;; the emacswiki (https://www.emacswiki.org/emacs/auto-capitalize.el). I have
;; tried to streamline the code, building on the refactoring process that Yuta
;; Yamada had already started, and removing/replacing old artifacts with their
;; modern equivalent. I have also modified the package’s interface to make it
;; simpler to use and to cover more cases.

;;; Code:

(require 'cl-lib)     ; cl-find
(require 'regexp-opt) ; regexp-opt
(require 'compat)     ; when-let*, set-local

(defconst auto-capitalize-version "3.0"
  "The version of auto-capitalize.el.")

(defgroup auto-capitalize nil
  "Customization group for the auto-capitalize package."
  :group 'convenience)


;; Internal variables:

(defvar auto-capitalize--match-data nil
  "Holds match data across recursive calls in `auto-capitalize-capitalize'.")

(defvar auto-capitalize--fixed-case-regexp nil
  "Cached regexp built from `auto-capitalize-fixed-case-words'.
Used by `auto-capitalize-maybe-capitalize-preceding-word' to avoid
rebuilding the regexp on every keystroke.")

(defvar auto-capitalize--abbrevs-regexp nil
  "Cached regexp built from `auto-capitalize-abbrevs'.
Used by `auto-capitalize-default-blocking-function' to avoid rebuilding
the regexp on every keystroke.")


;; Forward declarations to satisfy the compiler

(defvar auto-capitalize-ask)
(defvar auto-capitalize-yank)
(defvar auto-capitalize-strings)
(defvar auto-capitalize-start-of-inline-strings)
(defvar auto-capitalize-start-of-inline-comments)
(defvar auto-capitalize-comments)
(defvar auto-capitalize-outline-headings)
(defvar auto-capitalize-fixed-case-words)
(defvar auto-capitalize-abbrevs)
(defvar auto-capitalize-trigger-chars)
(defvar auto-capitalize-blocking-functions)


;; Internal functions:

(defun auto-capitalize-default-blocking-function ()
  "Return nil to block auto-capitalization in the current context.

Specifically, check the current buffer for the following conditions, and
return nil if any of them return nil:

1) It is not read-only

2) it is not a minibuffer

3) if in `prog-mode', the current text is either a comment or a string,
and the corresponding user option (`auto-capitalize-comments' or
`auto-capitalize-strings') is non-nil

4) if the previous word isn’t in `auto-capitalize-abbrevs'

5) the last typed character was one of
`auto-capitalize-trigger-chars' (skipped if that list is empty)."

  (and (not buffer-read-only)
       (not (minibufferp))

       ;; activate in prog-mode only if cursor is in string or comment.
       (or (not (derived-mode-p 'prog-mode))

           (and auto-capitalize-strings
                (nth 3 (syntax-ppss)))

           (and auto-capitalize-comments
                (nth 4 (syntax-ppss))))

       ;; do not activate after any word in
       ;; `auto-capitalize-abbrevs'
       (save-excursion
         (backward-word)
         (let ((word-start (point)))
           (not (and (re-search-backward
                      auto-capitalize--abbrevs-regexp
                      (line-beginning-position) t)
                     (= (match-end 0) word-start)))))

       ;; don’t capitalize words that look like "[a-z].[a-z].". This is
       ;; mainly to prevent capitalizing "i.e." or "e.g.")
       (not (and (eq last-command-event ?.)
                 (memq (char-before (max (point-min) (- (point) 2)))
                       '(?\s ?\( ?. ?\"))))

       ;; activate after only specific characters you type, or after yanking
       ;; text instead of typing
       (or (null auto-capitalize-trigger-chars)
           (not (memq this-command `(self-insert-command
                                     ,(command-remapping 'self-insert-command))))
           (memq last-command-event auto-capitalize-trigger-chars))))

(defun auto-capitalize-inserted-non-word-p (beg end length)
  "Return non-nil if the last event was an insertion of a non-word character.

BEG, END, and LENGTH are the position in the buffer where the change
started, where it ended, and the length of that section before the
change, respectively, as defined by the documentation of
`after-change-functions' (which see)."
  (condition-case error
      (or (memq this-command '(newline newline-and-indent))
          (and (or (memq this-command
                         `(self-insert-command
                           ,(command-remapping 'self-insert-command)))
                   (let ((key (this-command-keys)))
                     (and (eq (lookup-key global-map key t)
                              'self-insert-command)
                          (= length 0)
                          (= (- end beg) 1))))
               (or (not (equal (char-syntax last-command-event) ?w))
                   (and auto-capitalize-trigger-chars
                        (member last-command-event
                                auto-capitalize-trigger-chars)))))
    (error (message "auto-capitalize error: %S" error) nil)))

(defun auto-capitalize-capitalize (beg end length)
  "If `auto-capitalize-mode' is enabled, then start the capitalization logic.

This function is installed as an `after-change-function' by
`auto-capitalize-mode'. As such its three arguments are:

BEG, END: buffer positions where the changed text starts and ends,
respectively.

LENGTH: the length (in chars) of the pre-change text replaced by that
range. In practice, this is almost always zero, except when yanking text
and `auto-capitalize-yank' is non-nil.

This function serves as a dispatcher of other functions to decide if the
word before point (or the yanked text) should be capitalized."

  (condition-case error
      (when (or (null auto-capitalize-blocking-functions)
                (run-hook-with-args-until-failure
                 'auto-capitalize-blocking-functions))

        (cond ((auto-capitalize-inserted-non-word-p beg end length)
               ;; self-inserting, non-word character
               (when (and (> beg (point-min))
                          (equal (char-syntax (char-after (1- beg))) ?w))
                 (auto-capitalize-maybe-capitalize-preceding-word)))
              ((and auto-capitalize-yank
                    ;; `yank' sets `this-command' to t, and the
                    ;; after-change-functions are run before it has been
                    ;; reset:
                    (or (eq this-command 'yank)
                        (and (= length 0) ; insertion?
                             (eq this-command 't))))
               (save-excursion
                 (goto-char beg)
                 (save-match-data
                   (while (re-search-forward "\\Sw" end t)
                     (setq auto-capitalize--match-data (match-data))
                     ;; recursion!
                     (let* ((this-command 'self-insert-command)
                            (non-word-char (char-after (match-beginning 0)))
                            (last-command-event non-word-char))
                       (set-match-data auto-capitalize--match-data)
                       (auto-capitalize-capitalize (match-beginning 0)
                                                   (match-end 0)
                                                   0))))))))
    (error (message "auto-capitalize error: %S" error) nil)))

(defun auto-capitalize-handle-fixed-case (m-beg m-end)
  "Find the word between M-BEG and M-END and replace it with its fixed-case entry.

If the word between M-BEG and M-END is included, with its current case,
in `auto-capitalize-fixed-case-words', replace its occurrence in the
buffer with the one in the list. For example, using the default value of
the variable `auto-capitalize-fixed-case-words', typing \"i \" produces
\"I \"."

  (let ((lowercase-word (buffer-substring m-beg m-end)))
    (unless (member lowercase-word auto-capitalize-fixed-case-words)
      ;; capitalize!
      (undo-boundary)
      (when (or (not auto-capitalize-ask)
                (auto-capitalize--ask))
        (replace-match (cl-find lowercase-word
                                auto-capitalize-fixed-case-words
                                :key 'downcase
                                :test 'string-equal)
                       t t)))))

(defun auto-capitalize-check-triggers (text-start word-start)
  "Return non-nil if the word beginning at WORD-START should be capitalized.

In practice, TEXT-START is almost always one character before
WORD-START.

This function returns non-nil if the last command was an insertion of a
lower-case character, and any of the functions in
`auto-capitalize-trigger-functiions' returns non-nil.

In addition, if `auto-capitalize-ask' is non-nil, query the user and
only capitalize if the user answered \"y\"."

  (goto-char text-start)
  (and
   ;; inserting lowercase text?
   (let ((case-fold-search nil))
     (save-excursion
       (goto-char word-start)
       (looking-at "[[:lower:]]+")))

   ;; the user answered y when asked?
   (or (not auto-capitalize-ask)
       (auto-capitalize--ask))

   (run-hook-with-args-until-success
    'auto-capitalize-trigger-functions text-start word-start)))

(defun auto-capitalize-default-trigger-function (text-start word-start)
  "Check the context around TEXT-START/WORD-START.

This predicate returns non-nil if any of the following conditions hold:

1) TEXT-START is at the beginning of the buffer

2) WORD-START is the first char of a paragraph (identified through the
function `start-of-paragraph-text', which see)

3) WORD-START is the first char of a sentence (identified through the
function `bounds-of-thing-at-point', which see)

4) WORD-START is the first char after a heading, as defined by the
buffer-local value of `outline-regexp'.

5) in either `prog-mode' buffers, or `text-mode' buffers that have
markup syntax (Org, markdown, TeX...), the text of interest is inside a
comment, and `auto-capitalize-comments' is non-nil."

  (goto-char text-start)
  (or

   (and (derived-mode-p 'text-mode)
        (or (bobp)
            (and auto-capitalize-outline-headings
                 (bound-and-true-p outline-regexp)
                 (save-excursion
                   (goto-char (line-beginning-position))
                   (when (looking-at outline-regexp)
                     (goto-char (match-end 0))
                     (skip-syntax-forward "^w" (line-end-position))
                     (= (point) word-start))))

            ;; Beginning of line after an outline heading?
            (save-excursion
              (and (bound-and-true-p outline-regexp)
                   (zerop (forward-line -1))
                   (looking-at outline-regexp)))))

   ;; Beginning of paragraph?
   (= word-start
      (save-excursion
        (start-of-paragraph-text)
        (skip-syntax-forward "^w")
        (point)))

   ;; Beginning of a sentence?
   (when-let* ((bounds (car (bounds-of-thing-at-point 'sentence))))
     (= word-start
        (save-excursion
          (goto-char bounds)
          (skip-syntax-forward "^w")
          (point))))

   ;; Beginning of a string starting its own line (like docstrings)?
   (and auto-capitalize-strings
        (save-excursion
          (goto-char word-start)
          (when-let* ((string-start (nth 8 (syntax-ppss))))
            (and (or auto-capitalize-start-of-inline-strings
                     (progn (goto-char string-start)
                            (skip-chars-backward "\"'")
                            (skip-chars-backward " \t")
                            (bolp)))
                 (= word-start
                    (save-excursion
                      (goto-char string-start)
                      (skip-syntax-forward "^w")
                      (point)))))))

   ;; Beginning of a comment?
   ;; We need to check this here because org/tex comments don't play nice
   ;; with paragraph/sentence bounds
   (and auto-capitalize-comments
        (or (save-excursion
              (and comment-start-skip
                   (re-search-backward comment-start-skip nil t)
                   (= (match-end 0) text-start)
                   (or auto-capitalize-start-of-inline-comments
                       (save-excursion
                         (goto-char (match-beginning 0))
                         (skip-chars-backward " \t")
                         (bolp)))))
            (save-excursion
              (when-let* ((comment-start (nth 8 (syntax-ppss))))
                (and (or auto-capitalize-start-of-inline-comments
                         (save-excursion
                           (goto-char comment-start)
                           (skip-chars-backward " \t")
                           (bolp)))
                     (= word-start
                        (save-excursion
                          (goto-char comment-start)
                          (skip-syntax-forward "^w")
                          (point))))))))))

(defun auto-capitalize--ask ()
  "Ask the user whether the last typed word should be capitalized or not."
  (prog1 (y-or-n-p
          (format "Capitalize \"%s\"? "
                  (buffer-substring (match-beginning 0) (match-end 0))))
    (message "")))

(defun auto-capitalize-maybe-capitalize-preceding-word ()
  "Capitalize the word preceding point if either of the following conditions hold:

1) it appears capitalized in `auto-capitalize-fixed-case-words'

2) `auto-capitalize-check-triggers' returns non-nil."

  (save-excursion
    (forward-word -1)
    (save-match-data
      (let* ((word-start (point))
             (text-start
	      (progn
		(cl-loop while (or (minusp (skip-chars-backward "\""))
			           (minusp (skip-syntax-backward "\"("))))
		(point))))
        (cond ((and auto-capitalize--fixed-case-regexp
                    (let ((case-fold-search nil))
                      (goto-char word-start)
                      (looking-at auto-capitalize--fixed-case-regexp)))
               (auto-capitalize-handle-fixed-case (match-beginning 0) (match-end 0)))
              ((auto-capitalize-check-triggers
                text-start word-start)
               ;; capitalize!
               (undo-boundary)
               (goto-char word-start)
               (capitalize-word 1)))))))

(defun auto-capitalize--set-fixed-case (sym val &optional buffer-local)
  "Setter for `auto-capitalize-fixed-case-words'.

Updates it (SYM) with the new value (VAL) and rebuilds the cached regexp
`auto-capitalize--fixed-case-regexp'.

If BUFFER-LOCAL is non-nil, only set the buffer-local value."
  (if buffer-local
      (progn
        (set-local sym val)
        (setq-local auto-capitalize--fixed-case-regexp
                    (if val
                        (regexp-opt (mapcar #'downcase val) 'words)
                      nil)))
    (set-default sym val)
    (setq auto-capitalize--fixed-case-regexp
          (if val
              (regexp-opt (mapcar #'downcase val) 'words)
            nil))))

(defun auto-capitalize--set-abbrevs (sym val &optional buffer-local)
  "Setter for `auto-capitalize-abbrevs'.

Updates it (SYM) with the new value (VAL) and rebuilds the cached regexp
`auto-capitalize--abbrevs-regexp'.

If BUFFER-LOCAL is non-nil, only set the buffer-local value."
  (if buffer-local
      (progn
        (set-local sym val)
        (setq-local auto-capitalize--abbrevs-regexp
                    (if val
                        (concat "[[:punct:]]*"
                                (regexp-opt auto-capitalize-abbrevs)
                                "[^.[:space:]]*[[:space:]]")
                      nil)))
    (set-default sym val)
    (setq auto-capitalize--abbrevs-regexp
          (if val
              (concat "[[:punct:]]*"
                      (regexp-opt auto-capitalize-abbrevs)
                      "[^.[:space:]]*[[:space:]]")
            nil))))


;; Org mode: We need to handle org-mode source blocks specifically, since they
;; are code, but are technically still part of a text-mode buffer.

(declare-function org-in-src-block-p "org")

(defun auto-capitalize-org-blocking-function ()
  "Returns non-nil if not in org mode, or not inside an org source block.

This predicate is added to `auto-capitalize-blocking-functions' (which
see)."
  (or (not (derived-mode-p 'org-mode))
      (not (org-in-src-block-p))

      (and (nth 3 (syntax-ppss))
           auto-capitalize-strings)

      (and (nth 4 (syntax-ppss))
           auto-capitalize-comments)))


;; User options:

(defcustom auto-capitalize-ask nil
  "If non-nil, always ask before capitalizing."
  :group 'auto-capitalize
  :type 'boolean)

(defcustom auto-capitalize-yank nil
  "If non-nil, auto-capitalization applies to yanked text."
  :group 'auto-capitalize
  :type 'boolean)

(defcustom auto-capitalize-strings t
  "If non-nil, strings in `prog-mode' buffers will be capitalized.

This variable is checked by `auto-capitalize-default-trigger-function'."
  :group 'auto-capitalize
  :type 'boolean)

(defcustom auto-capitalize-start-of-inline-strings nil
  "If non-nil, capitalize the first word in inline strings.

An inline string is one that does not start on its own line.
For example, in Emacs Lisp mode:

    (setq x \"text\")

With this option set to t, the word \"text\" would be capitalized to
\"Text\".

When this option is nil (the default), only strings whose opening
delimiter is the first non-whitespace on their line are capitalized
\(like docstrings).

This variable is checked by `auto-capitalize-default-trigger-function'."
  :group 'auto-capitalize
  :type 'boolean)

(defcustom auto-capitalize-start-of-inline-comments t
  "If non-nil, capitalize the first word in inline comments.

An inline comment is one that follows code on the same line.
For example, in Emacs Lisp mode:

    (setq x 1) ; some text here

With this option set to t, the word \"some\" would be capitalized to
\"Some\".

This variable is checked by `auto-capitalize-default-trigger-function'."
  :group 'auto-capitalize
  :type 'boolean)

(defcustom auto-capitalize-comments t
  "If non-nil, comments in `prog-mode' buffers will be capitalized.

This variable is checked by `auto-capitalize-default-trigger-function'."
  :group 'auto-capitalize
  :type 'boolean)

(defcustom auto-capitalize-outline-headings t
  "If non-nil, the headings in `text-mode' buffers will be capitalized.

The check is done using the buffer-local value of `outline-regexp',
which see."
  :group 'auto-capitalize
  :type 'boolean)

(defcustom auto-capitalize-fixed-case-words '("I") ;  "Stallman" "GNU" "http"
  "If non-nil, a list of words that will always be in the case they appear in here.

If `auto-capitalize' mode is on, and as long as
`auto-capitalize-blocking-functions' pass, these words will be
automatically capitalized or upcased as listed (mixed case is allowable
as well), even if no other condition would get them capitalized.
Conversely, a word added in lowercase will never be automatically
capitalized. This is ensured by the function
`auto-capitalize-handle-fixed-case', which see"
  :group 'auto-capitalize
  :type '(repeat (string :tag "Word list"))
  :set #'auto-capitalize--set-fixed-case)

(defcustom auto-capitalize-abbrevs '("e.g." "i.e." "vs." "Mr." "Messrs." "Mrs." "Mmes." "Ms." "Mses.")
  "List of common abbreviations that shouldn’t count as sentence endings.
This means that they will not cause a word that comes after them to get
capitalized, unless it appears, capitalized, in
`auto-capitalize-fixed-case-words'.

This list is checked by `auto-capitalize-default-blocking-function',
which see."
  :group 'auto-capitalize
  :type '(repeat (string :tag "Non-sentence ending word."))
  :set #'auto-capitalize--set-abbrevs)

(defcustom auto-capitalize-trigger-chars '(?\s ?, ?. ?? ?' ?’ ?: ?\; ?- ?!)
  "List of chars that trigger auto-capitalization on the preceding word.

This variable is checked by `auto-capitalize-default-blocking-function'.

If this variable is nil, it is ignored."
  :group 'auto-capitalize
  :type
  '(choice (repeat (character
                    :tag "Characters that trigger capitalization on the preceding word"))
           (const nil)))

(defcustom auto-capitalize-inhibit-buffers nil
  "List of buffer names in which to suppress auto-capitalization."
  :group 'auto-capitalize
  :type '(repeat (string :tag "Buffer name")))

(defcustom auto-capitalize-blocking-functions
  (list #'auto-capitalize-default-blocking-function
        #'auto-capitalize-org-blocking-function)
  "Hook providing the right of first refusal over capitalization.

Each function is called with no arguments and should return nil to
block capitalization in the current context."
  :group 'auto-capitalize
  :type 'hook
  :options (list #'auto-capitalize-default-blocking-function
                 #'auto-capitalize-org-blocking-function))

(defcustom auto-capitalize-trigger-functions '(auto-capitalize-default-trigger-function)
  "Hook for triggering capitalization at specific buffer positions.

Each function is called with two arguments, (TEXT-START WORD-START), and
should return non-nil if the word at WORD-START should be capitalized.
The functions are OR'd together: if any returns non-nil, capitalization
occurs.

This hook complements `auto-capitalize-blocking-functions': blocking
functions run first and always take precedence.  Only if all blocking
functions pass are the trigger functions consulted."
  :group 'auto-capitalize
  :type 'hook
  :options (list #'auto-capitalize-default-trigger-function))


;; Commands:

;;;###autoload
(define-minor-mode auto-capitalize-mode
  "Toggle `auto-capitalize' minor mode in the current buffer.

This will install `auto-capitalize-capitalize' in
`after-change-functions' in the current buffer."

  :init-value nil
  :lighter " ACap"
  :keymap nil
  (cond
    ;; Turn off
    ((or (not auto-capitalize-mode)
         buffer-read-only
         (member (buffer-name) auto-capitalize-inhibit-buffers))
     (remove-hook 'after-change-functions 'auto-capitalize-capitalize t))

    ;; Turn on
    (t
     (add-hook 'after-change-functions #'auto-capitalize-capitalize nil t)
     (add-hook 'auto-capitalize-blocking-functions
               #'auto-capitalize-default-blocking-function))))

;;;###autoload
(define-globalized-minor-mode auto-capitalize-global-mode
  auto-capitalize-mode auto-capitalize-mode
  :predicate '(not comint-mode))



(provide 'auto-capitalize)
;;; auto-capitalize.el ends here
