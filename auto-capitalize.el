;;; auto-capitalize.el --- Automatic capitalization with batteries included -*- lexical-binding: t; -*-

;; Copyright   1998,2001,2002,2005 Kevin Rodgers
;; Copyright   2026 Abdulnafé Toulaïmat

;; Original Author: Kevin Rodgers <ihs_4664@yahoo.com>
;; (Please don’t contact original author if you found a bug in this
;; package)
;; Past maintainer: Yuta Yamada <cokesboy at gmail.com>

;; Maintainer: Abdulnafé Toulaïmat <abdulnafe.toulaimat@gmail.com>
;; Assisted-by: OpenCode:Big_Pickle
;; Package-Requires: ((emacs "28.1") (compat "31.0"))

;; Created: 20 May 1998
;; Package-Version: 3.1.3
;; Keywords: text, wp, convenience
;; URL: https://github.com/abdulnafe-t/auto-capitalize.el

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

;; `auto-capitalize-mode' is a minor mode that automatically capitalizes text as
;; you type. It does this at the start of sentences/paragraphs, as well as in
;; comments or strings in any `prog-mode' buffer, or indeed any buffer whose
;; major mode defines some syntax for comments (Org, TeX,...).
;;
;; A basic configuration using `use-package' might look like
;;
;;     (use-package auto-capitalize
;;       :init
;;       (auto-capitalize-global-mode))
;;
;; Or, to also use the Org, SGML, and TeX plugins (the latter requiring AUCTeX):
;;
;;     (use-package auto-capitalize
;;       :init
;;       (auto-capitalize-global-mode)
;;       :hook
;;       ((TeX-mode . auto-capitalize-tex-mode)
;;        (org-mode . auto-capitalize-org-mode)
;;        (sgml-mode . auto-capitalize-sgml-mode)))
;;
;; The heart of the package is `auto-capitalize-after-change', which is
;; installed in `after-change-functions' when the mode is enabled. It serves as
;; the main entry point for the capitalization logic, which is based on two
;; hooks that you can add your own predicates to.
;;
;; The `auto-capitalize-blocking-functions' hook gives you the right of first
;; refusal over capitalization: each function in that hook is called with two
;; arguments, TEXT-START and WORD-START, and returns non-nil to block
;; capitalization of the word at WORD-START. A single function in that hook
;; returning non-nil causes the check to fail and blocks capitalization. Note,
;; however, that even if every function in this hook returns nil, that does not
;; guarantee a word will be capitalized.
;;
;; By default, this hook only contains
;; `auto-capitalize-default-blocking-function'.
;;
;; The second hook is `auto-capitalize-trigger-functions'. These functions are
;; called with the same arguments as the blocking functions, and if any of them
;; return non-nil, capitalization occurs. By default, only
;; `auto-capitalize-default-trigger-function' is included in this hook.
;;
;; Note that the blocking functions take precedence: they are called first, and
;; only if they all return nil, the trigger functions get called.
;;
;; Additional plugins, like the provided `auto-capitalize-tex' and
;; `auto-capitalize-org', can add their own predicates buffer-locally.
;;
;; Alternatively, if you don't want to write whole new predicates, you can
;; always customize some of the user options in the `auto-capitalize' group.
;; Examples include `auto-capitalize-strings', which controls whether strings in
;; prog-mode should be auto-capitalized, and its comment analogue
;; `auto-capitalize-comments'.
;;
;; This package is a revamp of Yuta Yamada’s version
;; (https://github.com/yuutayamada/auto-capitalize-el), which is itself a fork
;; of the original auto-capitalize.el, written by Kevin Rodgers and shared on
;; the Emacs wiki (https://www.emacswiki.org/emacs/auto-capitalize.el). I have
;; tried to streamline the code, building on the refactoring process that Yuta
;; Yamada had already started, and removing/replacing old artifacts with their
;; modern equivalent. I have also modified the package’s interface to make it
;; simpler to use and to cover more cases.

;;; Code:

(require 'cl-lib)     ; cl-find
(require 'seq)        ; seq-difference
(require 'regexp-opt) ; regexp-opt
(require 'compat)     ; when-let*, set-local
(require 'thingatpt ) ; thing-at-point-uri-schemes, thing-at-point-file-at-point

(defconst auto-capitalize-version "3.1.3"
  "The version of auto-capitalize.el.")

(defgroup auto-capitalize nil
  "Customization group for the auto-capitalize package."
  :group 'convenience)


;;; Internal variables:

(defvar auto-capitalize--match-data nil
  "Holds match data across recursive calls in `auto-capitalize-after-change'.")

(defvar auto-capitalize--fixed-case-regexp nil
  "Cached regexp built from `auto-capitalize-fixed-case-words'.
Used by `auto-capitalize--maybe-capitalize' to avoid
rebuilding the regexp on every keystroke.")

(defvar auto-capitalize--abbrevs-regexp nil
  "Cached regexp built from `auto-capitalize-abbrevs'.
Used by `auto-capitalize-default-blocking-function' to avoid rebuilding
the regexp on every keystroke, and by
`auto-capitalize--downcase-ie' to detect abbrevs.")

(defvar auto-capitalize--lighter " AutoCap"
  "Mode-line lighter for `auto-capitalize-mode'.")

(defvar auto-capitalize--syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?' "." st)
    (modify-syntax-entry ?’ "." st)
    st)
  "Syntax table used when deciding whether to capitalize a word.")

(defvar auto-capitalize--uri-scheme (regexp-opt (mapcar (lambda(str)
                                                          (string-trim-right str "//"))
                                                        thing-at-point-uri-schemes))
  "Regexp matching URI schemes, without any trailing slashes.

This is used by `auto-capitalize-default-trigger-function'.")


;;; Forward declarations to satisfy the compiler

(defvar auto-capitalize-ask)
(defvar auto-capitalize-yank)
(defvar auto-capitalize-strings)
(defvar auto-capitalize-start-of-inline-strings)
(defvar auto-capitalize-start-of-inline-comments)
(defvar auto-capitalize-comments)
(defvar auto-capitalize-fixed-case-words)
(defvar auto-capitalize-abbrevs)
(defvar auto-capitalize-trigger-functions)
(defvar auto-capitalize-blocking-functions)
(defvar auto-capitalize-downcase-ie)

;; Used in the default blocking and trigger functions, as well as the plugins
(declare-function treesit-thing-at "treesit")
(declare-function treesit-language-at "treesit")
(declare-function treesit-node-start "treesit.c")


;;; Internal functions

(defun auto-capitalize--downcase-ie (abbrev-start abbrev-end)
  "Downcase the abbreviation \"i.e.\" between ABBREV-START and ABBREV-END.

If the user option `auto-capitalize-downcase-ie' is non-nil, and the
char at ABBREV-START is uppercase, downcase the whole abbreviation."

  (and auto-capitalize-downcase-ie
       (let ((abbrev-first-char (char-after abbrev-start)))
         (when (eq abbrev-first-char (upcase abbrev-first-char))
           (undo-boundary)
           (downcase-region abbrev-start abbrev-end)))))

(defun auto-capitalize--handle-fixed-case (beg end)
  "Replace the word between BEG and END with its fixed-case entry.

If the word between BEG and END is included in
`auto-capitalize-fixed-case-words', replace its occurrence in the buffer
with the one in the list. For example, using the default value of the
variable `auto-capitalize-fixed-case-words', typing \"i SPC\" produces \"I SPC\"."

  (let ((lowercase-word (buffer-substring beg end)))
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

(defun auto-capitalize--check-triggers (text-start word-start)
  "Return non-nil if the word beginning at WORD-START should be capitalized.

TEXT-START is the first open delimiter before WORD-START, having skipped
back over opening quotes and parens. If there are no such delimiters, it
matches WORD-START.

This function returns non-nil if the word starts with a lower-case
letter, and any function in `auto-capitalize-trigger-functions' returns
non-nil.

In addition, if `auto-capitalize-ask' is non-nil, query the user and
only capitalize if the user answered \"y\"."

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

(defun auto-capitalize--ask ()
  "Ask the user whether the last typed word should be capitalized or not."
  (prog1 (y-or-n-p
          (format "Capitalize \"%s\"? "
                  (buffer-substring (match-beginning 0) (match-end 0))))
    (message "")))

(defun auto-capitalize--maybe-capitalize (text-start word-start)
  "Capitalize the word at WORD-START if either of the following conditions hold:

1) it appears capitalized in `auto-capitalize-fixed-case-words'

2) `auto-capitalize--check-triggers' returns non-nil.

WORD-START is the position of the start of the word of interest, and
TEXT-START is the position before that, having skipped back over any
open quotes, parens, etc.

Alternatively, if the word is \"I.e.\", then it is downcased by calling
`auto-capitalize--downcase-ie'."

  (save-excursion
    (save-match-data
      (cond
       ((and auto-capitalize--fixed-case-regexp
             (let ((case-fold-search nil))
               (with-syntax-table auto-capitalize--syntax-table
                 (save-excursion
                   (goto-char word-start)
                   (and (looking-at auto-capitalize--fixed-case-regexp)
                        (let ((after (match-end 0)))
                          (or (>= after (point-max))
                              (not (eq (char-syntax (char-after after)) ?w)))))))))

        (auto-capitalize--handle-fixed-case (match-beginning 0) (match-end 0)))

       ;; HACK: we explicitly look for "I.e." in order to downcase it. The idea
       ;; is that simply typing "i.e." will automatically cause the "i" to get
       ;; capitalized, assuming "I" is in `auto-capitalize-fixed-case-words'. In
       ;; order to prevent that from happening if the user is actually typing
       ;; "i.e.", we always force this specific abbreviation to be lowercase.
       ;;
       ;; The price to pay is that even if the user types capital I, with the
       ;; intent of typing "I.e.", it still gets downcased.
       ((save-excursion
          (goto-char word-start)
          (skip-chars-backward "[[:alpha:]].")
          (let ((case-fold-search nil))
            (looking-at "I\\.e\\.")))

        (auto-capitalize--downcase-ie (match-beginning 0) (match-end 0)))

       ((auto-capitalize--check-triggers
         text-start word-start)
        ;; capitalize!
        (undo-boundary)
        (capitalize-word -1))))))

(defun auto-capitalize--set-fixed-case (sym val &optional buffer-local)
  "Setter for `auto-capitalize-fixed-case-words'.

Updates it (SYM) with the new value (VAL) and rebuilds the cached regexp
`auto-capitalize--fixed-case-regexp'.

If BUFFER-LOCAL is non-nil, only sets the buffer-local value."
  (if buffer-local
      (progn
        (set-local sym val)
        (setq-local auto-capitalize--fixed-case-regexp
                    (if val
                        (regexp-opt (mapcar #'downcase val) 'symbols)
                      nil)))
    (set-default sym val)
    (setq auto-capitalize--fixed-case-regexp
          (if val
              (regexp-opt (mapcar #'downcase val) 'symbols)
            nil))))

(defun auto-capitalize--set-abbrevs (sym val &optional buffer-local)
  "Setter for `auto-capitalize-abbrevs'.

Updates it (SYM) with the new value (VAL) and rebuilds the cached regexp
`auto-capitalize--abbrevs-regexp'.

If BUFFER-LOCAL is non-nil, only sets the buffer-local value."
  (if buffer-local
      (progn
        (set-local sym val)
        (setq-local auto-capitalize--abbrevs-regexp
                    (if val

                        ;; HACK: the extra groups around the abbrevs are here to
                        ;; make sure we can handle edge cases, like if the
                        ;; abbreviation is quoted, or if it appears as a
                        ;; substring of the previous word (for instance, if the
                        ;; previous word is "abbrevs.").

                        (concat "\\<"
                                (regexp-opt val)
                                "[^.[:space:]]*")
                      nil)))
    (set-default sym val)
    (setq auto-capitalize--abbrevs-regexp
          (if val
              (concat "\\<"
                      (regexp-opt val)
                      "[^.[:space:]]*")
            nil))))

(defun auto-capitalize--treesit-p ()
  "Return non-nil if tree-sitter is available."
  (and (bound-and-true-p treesit-primary-parser)
       (fboundp 'treesit-thing-at)
       (fboundp 'treesit-node-start)
       (fboundp 'treesit-language-at)))

(defun auto-capitalize--treesit-embedded-p (languages)
  "Return non-nil if point is in embedded code of one of LANGUAGES.

Only code is considered: if point is in a comment or a string, return nil."
  (and (auto-capitalize--treesit-p)
       (memq (treesit-language-at (point)) languages)
       (not (treesit-thing-at (point) "comment"))
       (not (treesit-thing-at (point) "string"))))


;;; User options

(defcustom auto-capitalize-ask nil
  "If non-nil, always ask before capitalizing."
  :type 'boolean)

(defcustom auto-capitalize-yank nil
  "If non-nil, auto-capitalization applies to yanked text."
  :type 'boolean)

(defcustom auto-capitalize-strings t
  "If non-nil, strings in `prog-mode' buffers will be capitalized.

This variable is checked by `auto-capitalize-default-trigger-function'
and `auto-capitalize-default-blocking-function'."
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
  :type 'boolean)

(defcustom auto-capitalize-start-of-inline-comments t
  "If non-nil, capitalize the first word in inline comments.

An inline comment is one that follows code on the same line.
For example, in Emacs Lisp mode:

    (setq x 1) ; some text here

With this option set to t, the word \"some\" would be capitalized to
\"Some\".

This variable is checked by `auto-capitalize-default-trigger-function'."
  :type 'boolean)

(defcustom auto-capitalize-comments t
  "If non-nil, comments in `prog-mode' buffers will be capitalized.

This variable is checked by `auto-capitalize-default-trigger-function'
and `auto-capitalize-default-blocking-function'."
  :type 'boolean)

(defcustom auto-capitalize-fixed-case-words '("I")
  "If non-nil, words that will always be in the case they appear in here.

If `auto-capitalize' mode is on, and as long as
`auto-capitalize-blocking-functions' pass, these words will be
automatically capitalized or upcased as listed (mixed case is allowed as
well), even if no other condition would get them capitalized.
Conversely, a word added in lowercase will always get downcased. This is
ensured by the function `auto-capitalize--handle-fixed-case', which see.

This list should be set with `setopt', the `customize' interface, the
`:custom' keyword in `use-package', or modified with
`auto-capitalize-add-fixed-case-words' or
`auto-capitalize-remove-fixed-case-words'. Changing it with `setq' or
`add-to-list' will not work correctly."

  :type '(repeat (string :tag "Word list"))
  :set #'auto-capitalize--set-fixed-case)

(defcustom auto-capitalize-abbrevs '("e.g." "i.e." "vs.")
  "List of common abbreviations that shouldn’t count as sentence endings.
This means that they will not cause a word that comes after them to get
capitalized, unless it appears, capitalized, in
`auto-capitalize-fixed-case-words'.

This list is checked by `auto-capitalize-default-blocking-function',
which see.

This list should be set with `setopt', the :custom keyword in
`use-package', the `customize' interface, or modified with
`auto-capitalize-add-abbrevs' or `auto-capitalize-remove-abbrevs'.
Changing it with `setq' or `add-to-list' will not work correctly."

  :type '(repeat (string :tag "Non-sentence ending word."))
  :set #'auto-capitalize--set-abbrevs)

(defcustom auto-capitalize-downcase-ie t
  "If non-nil, \"i.e.\" will always be downcased.

This is intended as a fix for the unfortunate side effect of the
combination of `auto-capitalize-fixed-case-words' containing \"I\", and
`auto-capitalize-abbrevs' containing \"i.e.\", leading to the latter
getting capitalized when it shouldn't."

  :type 'boolean)

(defcustom auto-capitalize-blocking-functions
  (list #'auto-capitalize-default-blocking-function)
  "Hook providing the right of first refusal over capitalization.

Each function is called with two arguments (TEXT-START WORD-START) and
should return non-nil to block capitalization in the current context.

This hook complements `auto-capitalize-trigger-functions': blocking
functions run first and always take precedence. Only if all blocking
functions pass are the trigger functions consulted.

Plugins like `auto-capitalize-org' and `auto-capitalize-tex' can add
their own blocking functions to this hook buffer-locally."
  :type 'hook
  :options (list #'auto-capitalize-default-blocking-function))

(defcustom auto-capitalize-trigger-functions
  '(auto-capitalize-default-trigger-function)
  "Hook for triggering capitalization at specific buffer positions.

Each function is called with two arguments, (TEXT-START WORD-START), and
should return non-nil if the word at WORD-START should be capitalized.
The functions are OR'd together: if any returns non-nil, capitalization
occurs.

This hook complements `auto-capitalize-blocking-functions': blocking
functions run first and always take precedence.  Only if all blocking
functions pass are the trigger functions consulted.

Plugins like `auto-capitalize-org' and `auto-capitalize-tex' can add
their own trigger functions to this hook buffer-locally."
  :type 'hook
  :options (list #'auto-capitalize-default-trigger-function))


;;; User-facing functions

(defun auto-capitalize-default-blocking-function (_text-start word-start)
  "Block auto-capitalization if the context demands it.

TEXT-START and WORD-START are the positions of the start of the current
text and the start of the current word, respectively.

Specifically, check the current buffer for the following conditions, and
return non-nil to block capitalization if any of them hold:

1) it is read-only

2) it is a minibuffer

3) if `thing-at-point-file-at-point' returns non-nil

4) if the word at WORD-START matches `auto-capitalize--uri-scheme'

5) if in `text-mode', capitalizing text other than comments or strings
is not blocked, while capitalization in comments/strings is similarly
gated by the corresponding user options. If outside of `text-mode', the
current text is in neither a comment nor a string, or it is but the
corresponding user option (`auto-capitalize-comments' or
`auto-capitalize-strings') is nil.

6) if the word preceding WORD-START is in `auto-capitalize-abbrevs'

7) the last typed character has word syntax (see the docstring of
`modify-syntax-entry', as well as the Info node `(elisp)Syntax Tables')."

  (or buffer-read-only
      (minibufferp)
      (save-excursion
        (goto-char word-start)
        (or

         ;; Don't capitalize filepaths
         (thing-at-point-file-at-point)

         ;; Don't capitalize URI schemes
         (looking-at auto-capitalize--uri-scheme)

         ;; If in text-mode, don't block if outside of comments or strings, and
         ;; only block inside comments or strings if the corresponding option is
         ;; nil.
         ;;
         ;; If not in text-mode (if in prog-mode), don't block inside comments
         ;; or strings if the corresponding option is non-nil, but block
         ;; everything else.
         ;;
         ;; NOTE: the text-mode check must come first, so that plain text in
         ;; modes that derive from both text-mode and prog-mode (such as
         ;; `mhtml-ts-mode') does not get blocked

         (let* ((syntax-ppss (syntax-ppss))
                (treesit-p (auto-capitalize--treesit-p))
                (in-string (or (nth 3 syntax-ppss)
                               (and treesit-p
                                    (treesit-thing-at (point) "string"))))
                (in-comment (or (nth 4 syntax-ppss)
                                (and treesit-p
                                     (treesit-thing-at (point) "comment")))))
           (if (derived-mode-p 'text-mode)
               (or
                (and (not auto-capitalize-strings) in-string)
                (and (not auto-capitalize-comments) in-comment))
             (and
              (or (not auto-capitalize-strings) (not in-string))
              (or (not auto-capitalize-comments) (not in-comment)))))

         ;; Block capitalization after any word in `auto-capitalize-abbrevs',
         ;; unless the current word is one in `auto-capitalize-fixed-case-words'
         (with-syntax-table auto-capitalize--syntax-table
           (and
            (not (looking-at auto-capitalize--fixed-case-regexp))
            (re-search-backward
             auto-capitalize--abbrevs-regexp
             (line-beginning-position) t)
            (= (1+ (match-end 0)) word-start)))))

      ;; Block capitalization if inserting chars with word-syntax.
      (and
       ;; We explicitly check for `this-command' being nil, otherwise the `memq'
       ;; test below would pass if command-remapping returns nil:
       ;; (memq nil '(self-insert-command nil)) => t
       this-command
       (memq this-command `(self-insert-command
                            ,(command-remapping 'self-insert-command)))

       (characterp last-command-event)
       (with-syntax-table auto-capitalize--syntax-table
         (eq (char-syntax last-command-event) ?w)))))

(defun auto-capitalize-default-trigger-function (text-start word-start)
  "Check whether to capitalize the word at WORD-START.

This predicate returns non-nil if any of the following conditions hold:

1) in `text-mode', TEXT-START is at the beginning of the buffer, or
matches `outline-regexp'

2) WORD-START is the first word of a paragraph, as identified by either
`start-of-paragraph-text', or a simple newline preceding the word

3) WORD-START is the first char of a sentence, identified through the
function `bounds-of-thing-at-point'. If that function returns nil, check
to see if the preceding text matches the return value of function
`sentence-end'

4) WORD-START is the first word of a comment. This is gated by
`auto-capitalize-comments' (and
`auto-capitalize-start-of-inline-comments', if the comment is inline)

5) WORD-START is the first word of a string. This is gated by
`auto-capitalize-strings' (and
`auto-capitalize-start-of-inline-strings', if the string is inline)."

  (save-excursion
    (goto-char text-start)
    (or

     (and (derived-mode-p 'text-mode)
          (or (bobp)
              (and (bound-and-true-p outline-regexp)
                   (save-excursion
                     (beginning-of-line)
                     (when (looking-at outline-regexp)
                       (goto-char (match-end 0))
                       (skip-syntax-forward "^w" (line-end-position))
                       (= word-start (point)))))))

     ;; Beginning of paragraph?
     (or (= word-start
            (save-excursion
              (start-of-paragraph-text)
              (skip-syntax-forward "^w")
              (point)))
         (save-excursion
           (goto-char word-start)
           (skip-syntax-backward "\s")
           (backward-char)
           (looking-at "\n")))

     ;; Beginning of a sentence?
     (if-let* ((bounds (car (bounds-of-thing-at-point 'sentence))))
         (= word-start
            (save-excursion
              (goto-char bounds)
              (skip-syntax-forward "^w")
              (point)))
       (save-excursion
         (skip-syntax-backward "^w" (line-beginning-position))
         (looking-at (sentence-end))))

     (save-excursion
       (goto-char word-start)
       (let* ((syntax-ppss (syntax-ppss))
              (treesit-p (auto-capitalize--treesit-p)))
         (or
          ;; Beginning of a comment?
          (and auto-capitalize-comments
               auto-capitalize-start-of-inline-comments
               (save-excursion
                 (when-let* ((comment-start
                              (or
                               (and (nth 4 syntax-ppss)
                                    (nth 8 syntax-ppss))
                               (and treesit-p
                                    (treesit-node-start (treesit-thing-at word-start "comment"))))))
                   (= word-start
                      (save-excursion
                        (goto-char comment-start)
                        (skip-syntax-forward "^w")
                        (point))))))

          ;; Beginning of a string?
          (and auto-capitalize-strings
               (save-excursion
                 (when-let* ((string-start
                              (or
                               (and (nth 3 syntax-ppss)
                                    (nth 8 syntax-ppss))
                               (and treesit-p
                                    (treesit-node-start (treesit-thing-at word-start "string"))))))
                   (and (or auto-capitalize-start-of-inline-strings
                            (progn (goto-char string-start)
                                   (skip-chars-backward "\"'")
                                   (skip-chars-backward " \t")
                                   (bolp)))
                        (= word-start
                           (save-excursion
                             (goto-char string-start)
                             (skip-syntax-forward "^w")
                             (point)))))))))))))

(defun auto-capitalize-after-change (beg end length)
  "If `auto-capitalize-mode' is enabled, then start the capitalization logic.

This function is installed in the `after-change-functions' hook by
`auto-capitalize-mode'. As such its three arguments are:

BEG, END: buffer positions where the changed text starts and ends,
respectively.

LENGTH: the length (in chars) of the pre-change text replaced by that
range. In practice, this is almost always zero, except when yanking text
and `auto-capitalize-yank' is non-nil, or when overwriting text.

This function serves as a dispatcher of other functions to decide if the
word before point (or the yanked text) should be capitalized."

  (condition-case error
      (let* ((word-start
              (save-excursion
                (forward-word -1)
                (point)))
             (text-start
              (save-excursion
                (goto-char word-start)
                (cl-loop while (or (< (skip-chars-backward "\"") 0)
                                   (< (skip-syntax-backward "\"(") 0)))
                (point))))
        (when (or (null auto-capitalize-blocking-functions)
                  (not (run-hook-with-args-until-success
                        'auto-capitalize-blocking-functions text-start word-start)))

          (cond
           ;; We need to check for yanking before checking for trigger chars,
           ;; because if the yanked text ends in a trigger char, only that
           ;; trigger char gets processed, meaning the rest of the text does
           ;; not get capitalized correctly.
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
                    (auto-capitalize-after-change (match-beginning 0)
                                                  (match-end 0)
                                                  0))))))

           ;; Self-inserting a non-word character?
           ((and (= length 0)
                 (> end beg)
                 (with-syntax-table auto-capitalize--syntax-table
                   (not (eq (char-syntax (char-before end)) ?w))))

            (and (> beg (point-min))
                 (with-syntax-table auto-capitalize--syntax-table
                   (eq (char-syntax (char-before beg)) ?w))
                 (auto-capitalize--maybe-capitalize
                  text-start word-start))))))
    (error (message "auto-capitalize error: %S" error) nil)))


;; Commands

(defun auto-capitalize-add-abbrevs (abbrevs &optional buffer-local)
  "Add one or more abbreviations to `auto-capitalize-abbrevs'.

ABBREVS is either a string or a list of strings to be added to
`auto-capitalize-abbrevs'. If BUFFER-LOCAL is non-nil (such as with a
prefix arg), the new abbrevs are added buffer-locally only.

If called interactively, prompts for a single string to add."

  (interactive
   (list (read-string "Abbreviation to add: ")
         current-prefix-arg))
  (setq abbrevs (ensure-list abbrevs))
  (auto-capitalize--set-abbrevs 'auto-capitalize-abbrevs
                                (append abbrevs auto-capitalize-abbrevs)
                                buffer-local)
  (message "%s" auto-capitalize-abbrevs))

(defun auto-capitalize-add-fixed-case-words (words &optional buffer-local)
  "Add one or more fixed-case words to `auto-capitalize-fixed-case-words'.

WORDS is either a string or a list of strings to be added to
`auto-capitalize-fixed-case-words'. If BUFFER-LOCAL is non-nil (such as
with a prefix arg), the new words are added buffer-locally only.

If called interactively, prompts for a single string to add."

  (interactive
   (list (read-string "Abbreviation to add: ")
         current-prefix-arg))
  (setq words (ensure-list words))
  (auto-capitalize--set-fixed-case 'auto-capitalize-fixed-case-words
                                   (append words auto-capitalize-fixed-case-words)
                                   buffer-local)
  (message "%s" auto-capitalize-fixed-case-words))

(defun auto-capitalize-remove-abbrevs (abbrevs &optional buffer-local)
  "Remove one or more abbreviations from `auto-capitalize-abbrevs'.

ABBREVS is either a string or a list of strings to be removed. If
BUFFER-LOCAL is non-nil (such as with a prefix arg), the change applies
buffer-locally only.

Interactively, uses completion to select an existing abbreviation."
  (interactive
   (list (completing-read
          "Abbreviation to remove: "
          (lambda (string pred action)
            (if (eq action 'metadata)
                '(metadata (category . auto-capitalize-abbrev))
              (complete-with-action action
                                    auto-capitalize-abbrevs string pred)))
          nil t)
         current-prefix-arg))
  (setq abbrevs (ensure-list abbrevs))
  (dolist (abbrev abbrevs)
    (unless (member abbrev auto-capitalize-abbrevs)
      (error "%s is not in auto-capitalize-abbrevs" abbrev)))
  (auto-capitalize--set-abbrevs 'auto-capitalize-abbrevs
                                (seq-difference auto-capitalize-abbrevs
                                                abbrevs)
                                buffer-local)
  (message "%s" auto-capitalize-abbrevs))

(defun auto-capitalize-remove-fixed-case-words (words &optional buffer-local)
  "Remove one or more words from `auto-capitalize-fixed-case-words'.

WORDS is either a string or a list of strings to be removed. If
BUFFER-LOCAL is non-nil (such as with a prefix arg), the change applies
buffer-locally only.

Interactively, uses completion to select an existing word."
  (interactive
   (list (completing-read
          "Fixed-case word to remove: "
          (lambda (string pred action)
            (if (eq action 'metadata)
                '(metadata (category . auto-capitalize-fixed-case-words))
              (complete-with-action action
                                    auto-capitalize-fixed-case-words string pred)))
          nil t nil nil nil t)
         current-prefix-arg))
  (setq words (ensure-list words))
  (dolist (word words)
    (unless (member word auto-capitalize-fixed-case-words)
      (error "%s is not in auto-capitalize-fixed-case-words" word)))
  (auto-capitalize--set-fixed-case 'auto-capitalize-fixed-case-words
                                   (seq-difference auto-capitalize-fixed-case-words
                                                   words)
                                   buffer-local)
  (message "%s" auto-capitalize-fixed-case-words))

;;;###autoload
(define-minor-mode auto-capitalize-mode
  "Toggle `auto-capitalize' minor mode in the current buffer.

This will install `auto-capitalize-after-change' in the current buffer's
 `after-change-functions'.

If the current buffer is a temp buffer, that is, if its name begins with
a space, this command does nothing."

  :init-value nil
  :lighter auto-capitalize--lighter
  :keymap nil
  (cond
   ;; Turn off
   ((not auto-capitalize-mode)
    (remove-hook 'after-change-functions #'auto-capitalize-after-change t))

   ;; Ephemeral/temp buffer; refuse to enable. A buffer whose name starts with a
   ;; space is usually a temp buffer, unless it's visiting a file whose name
   ;; starts with a space.
   ;;
   ;; NOTE: In practice, a buffer visiting such a file gets a "|" prepended to
   ;; its name, so the buffer-file-name guard is probably unnecessary.
   ((and (null buffer-file-name)
         (eq (aref (buffer-name (current-buffer)) 0) ?\s))
    (auto-capitalize-mode -1))

   ;; Turn on
   (t
    (add-hook 'after-change-functions #'auto-capitalize-after-change nil t))))

;;;###autoload
(define-globalized-minor-mode auto-capitalize-global-mode
  auto-capitalize-mode auto-capitalize-mode
  :predicate '(;; We exclude a number of modes derived from `text-mode' (and
               ;; some from `prog-mode'), because we know that auto-cap would
               ;; make too many mistakes in such modes. These are either modes
               ;; with syntax that auto-cap can't handle on its own, requiring a
               ;; plugin, or modes aimed at data serialization where "strings"
               ;; are really keys that shouldn't be capitalized.
               ;;
               ;; There's also a couple of misc. modes, such as `bib-mode.'
               ;;
               ;; This is meant to be defensive: we only enable auto-cap where
               ;; we know it can work. Any plugin that teaches auto-cap about
               ;; these modes will need to activate `auto-capitalize-mode'
               ;; itself.

               (not
                ;; (AUCTeX) Unsupported without `auto-capitalize-tex-mode'
                TeX-mode
                ;; (Builtin) Unsupported.
                tex-mode

                ;; This mode requires `auto-capitalize-sgml-mode'. Derived
                ;; modes include `html-mode', `html-ts-mode',
                ;; `heex-ts-mode', and `mhtml-ts-mode'.
                sgml-mode

                ;; Unsupported without `auto-capitalize-org-mode'
                org-mode

                ;; Unsupported without `auto-capitalize-xml-mode'
                nxml-mode

                ;; TODO: we should add plugins to support these.
                texinfo-mode
                php-mode

                ;; Technically text-modes, but capitalization
                ;; doesn't make much sense. Likely to stay excluded.
                css-base-mode
                nroff-mode
                conf-mode
                toml-mode
                yaml-mode
                json-mode

                ;; FIXME: is it really necessary to exclude these?
                bib-mode
                icalendar-mode)

               ;; NOTE: the excluded modes should come before the included ones.
               text-mode prog-mode))


(provide 'auto-capitalize)
;;; auto-capitalize.el ends here
