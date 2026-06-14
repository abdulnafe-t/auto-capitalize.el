;;; auto-capitalize.el --- Automatically capitalize (or upcase) words -*- lexical-binding: t; -*-

;; Copyright   1998,2001,2002,2005 Kevin Rodgers
;; Copyright   2026 Abdulnafé Toulaïmat

;; Original Author: Kevin Rodgers <ihs_4664@yahoo.com>
;; (Please don’t contact original author if you found a bug in this
;; package)
;; Past maintainer: Yuta Yamada <cokesboy at gmail.com>
;; Maintainer: Abdulnafé Toulaïmat <abdulnafe.toulaimat@gmail.com>
;; Package-Requires: ((emacs "24.3") (cl-lib "0.5"))

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

;; When the `auto-capitalize' minor mode is enabled, the first word at the
;; beginning of a paragraph or sentence is automatically capitalized when a
;; following whitespace or punctuation character is inserted. The same is true
;; of the first word of a comment or a string in any `prog-mode' buffers where
;; `auto-capitalize-mode' is enabled.
;;
;; To install auto-capitalize.el, copy it to a `load-path' directory, then add
;; this to your .emacs:
;
;;     (require 'auto-capitalize)
;;
;; Then, to turn on (unconditional) capitalization in all `text-mode' buffers,
;; as well as in comments and strings in `prog-mode' buffers, add this to your
;; .emacs:
;;
;;     (auto-capitalize-global-mode)
;;
;; Or, with `use-package':
;;
;;     (use-package auto-capitalize
;;         :init
;;         (auto-capitalize-global-mode))
;;
;; to enable the mode globally, or
;;
;;     (use-package auto-capitalize
;;         :hook
;;         (prog-mode-hook . auto-capitalize-mode)
;;         (text-mode-hook . auto-capitalize-mode))
;;
;; to only enable the mode in specific modes (such as text- and prog-mode in
;; this case).
;;
;; To trigger capitalization for contractions (such as I’ve, I’m, etc.) in
;;     text-mode buffers, add the following to your init.el:
;;
;;     ; For ASCII-style apostrophe
;;     (modify-syntax-entry ?' ". " text-mode-syntax-table)
;;
;;     ; For UNICODE curly apostrophe
;;     (modify-syntax-entry ?’ ". " text-mode-syntax-table)
;;
;; The decision on whether or not a word should be capitalized is handled by
;; predicate functions: `auto-capitalize-capitalize' calls all functions in
;; `auto-capitalize-predicate-functions' in turn, until one returns nil. If they
;; all return non-nil, it proceeds with capitalization.
;;
;; By default, this hook only contains
;; `auto-capitalize-default-predicate-function' and, once org is loaded,
;; `auto-capitalize-org-mode-predicate'. You can always write your own
;; predicates and add them to this hook.
;;
;; The `auto-capitalize-fixed-case-words' variable can be customized to specify
;;certain words that should always be in a specific case, regardless of their
;;position in the text. Any word that is added to this list in lowercase will be
;;skipped when capitalizing, while any word that is added in uppercase (or mixed
;;case) will be replaced in text by its version in the list. By default, this
;;contains the english pronoun "I".
;;
;; If a word is included, in upper case, in `auto-capitalize-fixed-case-words',
;; and you want to prevent it from getting capitalized one time, type the word,
;; then use `quoted-insert' (bound to `C-q' by default) followed by the next
;; punctuation or space character.

;; Package interface:

(require 'cl-lib) ; cl-find, cl-minusp
(require 'regexp-opt) ; regexp-opt

(defconst auto-capitalize-version "3.0"
  "The version of auto-capitalize.el.")


;; User options:

(defgroup auto-capitalize nil
  "auto-capitalize customization group"
  :group 'convenience)

(defcustom auto-capitalize-ask nil
  "If non-nil, always ask before capitalizing."
  :group 'auto-capitalize
  :type 'boolean)

(defcustom auto-capitalize-fixed-case-words '("I");  "Stallman" "GNU" "http"
  "If non-nil, a list of words that will always be in the case they appear
in here.

If `auto-capitalize' mode is on, these words will be automatically
capitalized or upcased as listed (mixed case is allowable as well), even
if no other condition would get them capitalized. Conversely, a word
added in lowercase will never be automatically capitalized."
  :group 'auto-capitalize
  :type '(repeat (string :tag "Word list")))

(defcustom auto-capitalize-not-sentence-endings '("e.g." "i.e." "vs.")
  "List of words that shouldn’t count as sentence ending, even though they
contain a period. This means that they will not cause a word that comes
after them to get capitalized, unless it appears, capitalized, in
`auto-capitalize-fixed-case-words'."
  :group 'auto-capitalize
  :type '(repeat (string :tag "Non-sentence ending word.")))

(defcustom auto-capitalize-trigger-chars '(?\  ?, ?. ?? ?' ?’ ?: ?\; ?- ?!)
  "List of chars that trigger auto-capitalization on the preceding word.
If set to nil, this variable is ignored when deciding whether to
auto-capitalize a word."
  :group 'auto-capitalize
  :type
  '(choice (repeat (character
                    :tag "Characters that trigger capitalization on the preceding word"))
           (const nil)))

(defcustom auto-capitalize-inhibit-buffers nil
  "List of buffer names in which to suppress auto-capitalization."
  :group 'auto-capitalize
  :type '(repeat (string :tag "Buffer name")))

(defcustom auto-capitalize-predicate-functions
  (list #'auto-capitalize-default-predicate-function)
  "This is a hook whose functions are called by
`auto-capitalize-capitalize' (which see). They should take no arguments,
and return non-nil if auto-capitalization should happen in the current
context."
  :group 'auto-capitalize
  :type 'hook
  :options (list #'auto-capitalize-default-predicate-function))


;; Internal variables:

(defvar auto-capitalize--match-data nil
  "Internal variable used to hold match data across recursive calls in
`auto-capitalize-capitalize' (which see).")

(defconst auto-capitalize-regex-lower "[[:lower:]]+")
(defconst auto-capitalize-abbrev-regexp
  "\\<\\([[:upper:]]?[[:lower:]]+\\.\\)+\\=")


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
    (remove-hook 'after-change-functions 'auto-capitalize-capitalize t)
    (add-hook 'auto-capitalize-predicate-functions
              #'auto-capitalize-default-predicate-function nil t))
   ;; Turn on
   (t
    (add-hook 'after-change-functions #'auto-capitalize-capitalize nil t)
    (add-hook 'auto-capitalize-predicate-functions
              #'auto-capitalize-default-predicate-function nil t))))

;;;###autoload
(define-globalized-minor-mode auto-capitalize-global-mode
  auto-capitalize-mode auto-capitalize-mode
  :predicate '(not comint-mode))


;; Internal functions:

(defun auto-capitalize-default-predicate-function ()
  "Return non-nil if auto-capitalization should happen in the current
context.

Specifically, check the following conditions for the current buffer, and
return non-nil if they are all non-nil:

1) It is not read-only

2) it is not a minibuffer

3) if in `prog-mode', the current text is either a comment or a string

4) if the previous word isn’t \"e.g.\", \"i.e.\" or the like

5) the last typed character was one of
`auto-capitalize-trigger-chars' (skipped if that list is empty)."

  (and (not buffer-read-only)
       (not (minibufferp))
       ;; activate if prog-mode and cursor is in string or comment.
       (if (derived-mode-p 'prog-mode)
           (and (derived-mode-p 'prog-mode)
                (save-excursion (nth 8 (syntax-ppss))))
         t)

       ;; do not activate after any word in
       ;; `auto-capitalize-not-sentence-endings'
       (save-excursion
         (backward-word)
         (not (looking-back
               (concat
                (regexp-opt auto-capitalize-not-sentence-endings)
                "[[:space:][:punct:]]*")
               (line-beginning-position) t)))

       ;; don’t capitalize words that look like "[a-z].[a-z].". This is
       ;; mainly to prevent capitalizing "i.e." or "e.g.")
       (not (and (eq last-command-event ?.)
                 (memq (char-before (max (point-min) (- (point) 2)))
                       '(?\  ?\( ?. ?\"))))

       ;; activate after only specific characters you type
       (or (null auto-capitalize-trigger-chars)
           (member last-command-event auto-capitalize-trigger-chars))))

(defun auto-capitalize-inserted-non-word-p (beg end length)
  "Check to see that the last event was a `self-insert-command' of a
non-word character.

BEG, END, and LENGTH are the position in the buffer where the change
started, where it ended, and the length of that section before the
change, respectively, as defined by `after-change-functions'."
  (condition-case error
      (or (and (or (eq this-command 'self-insert-command)
                   (let ((key (this-command-keys)))
                     (and (eq (lookup-key global-map key t)
                              'self-insert-command)
                          (= length 0)
                          (= (- end beg) 1))))
               (not (equal (char-syntax last-command-event) ?w)))
          (memq this-command '(newline newline-and-indent)))
    (error error)))

(defun auto-capitalize-capitalize (beg end length)
  "If `auto-capitalize-mode' is enabled, then capitalize the previous word.
The previous word is capitalized (or upcased) if it is a member of the
`auto-capitalize-fixed-case-words' list; or if it begins a paragraph or
sentence.

Capitalization occurs only if the current command was invoked via a
self-inserting non-word character (e.g. whitespace or punctuation).

Capitalization can be disabled in specific contexts via the
`auto-capitalize-predicate-functions' hook.

This should be installed as an `after-change-function', which
`auto-capitalize-mode' does when it is enabled."
  (condition-case error
      (when (and auto-capitalize-mode
                 (or (null auto-capitalize-predicate-functions)
                     (run-hook-with-args-until-failure
                      'auto-capitalize-predicate-functions)))

        (cond ((auto-capitalize-inserted-non-word-p beg end length)
               ;; self-inserting, non-word character
               (when (and (> beg (point-min))
                          (equal (char-syntax (char-after (1- beg))) ?w))
                 (auto-capitalize-maybe-capitalize-preceding-word)))))
    (error error)))

(defun auto-capitalize-handle-fixed-case (m-beg m-end)
  "Find the word between M-BEG and M-END and capitalize it, unless it is
included, in lowercase, in `auto-capitalize-fixed-case-words'."
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

(defun auto-capitalize-check-context (text-start word-start)
  "Check the context around TEXT-START and return non-nil if the word
beginning at WORD-START should be capitalized. In practice, TEXT-START
is almost always one character before WORD-START.

This function returns non-nil if the last command was an insertion of a
lower-case character, and any of the following conditions hold:

1) TEXT-START is at the beginning of the buffer

2) TEXT-START is the first char of a paragraph

3) TEXT-START is the first char of a sentence (identified through
`sentence-end', which see)

4) in `prog-mode' buffers, the text of interest is inside a comment or a
string

5) `auto-capitalize-ask' is non-nil and the user answered \"y\" when
queried."

  (goto-char text-start)
  (and (or (bobp)

           ;; beginning of paragraph?
           (and (= (current-column) left-margin)
                (or (save-excursion
                      (and (zerop (forward-line -1))
                           (looking-at paragraph-separate)))
                    (save-excursion
                      (and (re-search-backward paragraph-start
                                               nil t)
                           (= (match-end 0) text-start)
                           (= (current-column) left-margin)))))

           ;; beginning of sentence?
           (save-excursion
             (save-restriction
               (narrow-to-region (point-min) word-start)
               (and (re-search-backward (sentence-end)
                                        nil t)
                    (= (match-end 0) text-start)
                    ;; verify: preceded by whitespace?
                    (let ((previous-char (char-before text-start)))
                      ;; In some modes, newline (^J, aka LFD) is comment-end,
                      ;; not whitespace:
                      (or (eq ?\n previous-char)
                          (eq ?\  (char-syntax previous-char))))
                    ;; verify: not preceded by an abbreviation?
                    (let ((case-fold-search nil)
                          (abbrev-regexp auto-capitalize-abbrev-regexp))
                      (goto-char
                       (1+ (match-beginning 0)))
                      (or (not
                           (re-search-backward abbrev-regexp nil t))
                          (not
                           (member (match-string 0) auto-capitalize-fixed-case-words)))))))

           ;; beginning of a string?
           (and (derived-mode-p 'prog-mode)
                (or
                 (progn
                   (goto-char word-start)
                   (when-let* ((string-start
                                (nth 8 (syntax-ppss))))
                     (eq (1+ string-start) word-start)))

                 ;; beginning of a comment?
                 (and
                  (re-search-backward comment-start-skip nil t)
                  (= (match-end 0) word-start)))))

       ;; inserting lowercase text?
       (let ((case-fold-search nil))
         (goto-char word-start)
         (looking-at auto-capitalize-regex-lower))
       (and auto-capitalize-mode
            (or (not auto-capitalize-ask)
                (auto-capitalize--ask)))))

(defun auto-capitalize--ask ()
  "Ask the user whether the last typed word should be capitalized or not."
  (prog1 (y-or-n-p
          (format "Capitalize \"%s\"? "
                  (buffer-substring (match-beginning 0) (match-end 0))))
    (message "")))

(defun auto-capitalize-maybe-capitalize-preceding-word ()
  "Capitalize the word preceding point if either of the following conditions hold:

1) it appears capitalized in `auto-capitalize-fixed-case-words'

2) `auto-capitalize-check-context' returns non-nil."

  (save-excursion
    (forward-word -1)
    (save-match-data
      (let* ((word-start (point))
             (text-start
	      (progn
		(while (or (minusp (skip-chars-backward "\""))
			   (minusp (skip-syntax-backward "\"(")))
		  t)
		(point))))
        (cond ((and auto-capitalize-fixed-case-words
                    (let ((case-fold-search nil))
                      (goto-char word-start)
                      (looking-at
                       (concat "\\("
                               (mapconcat 'downcase
                                          auto-capitalize-fixed-case-words
                                          "\\|")
                               "\\)\\>"))))
               (auto-capitalize-handle-fixed-case (match-beginning 1) (match-end 1)))
              ((auto-capitalize-check-context
                text-start word-start)
               ;; capitalize!
               (undo-boundary)
               (goto-char word-start)
               (capitalize-word 1)))))))


;; Org mode: We need to handle org-mode source blocks specifically, since they are code,
;; but are technically still part of a text-mode buffer.
;;
;; This has the downside of preventing strings/comments in such blocks from getting
;; capitalized correctly.

(declare-function org-in-src-block-p "org")

(defun auto-capitalize-org-mode-predicate ()
  "Returns non-nil if not in org mode, or if inside an org source block.

This predicate is added to `auto-capitalize-predicate-functions' (which
see) when `org' is loaded."
  (or (not (eq major-mode 'org-mode))
      (not (org-in-src-block-p))))

;; Org mode src blocks
(with-eval-after-load "org"
  (add-hook 'auto-capitalize-predicate-functions #'auto-capitalize-org-mode-predicate))


;; Old package description, by Yuta Yamada:

;; This project was copied from emacswiki page
;; (https://www.emacswiki.org/emacs/auto-capitalize.el) and I changed
;; some details. Big difference is this package requires Emacs 24.3 or
;; higher version.

;; In `auto-capitalize' minor mode, the first word at the beginning of
;; a paragraph or sentence (i.e. at `left-margin' on a line following
;; `paragraph-separate', after `paragraph-start' at `left-margin', or
;; after `sentence-end') is automatically capitalized when a following
;; whitespace or punctuation character is inserted.
;;
;; The `auto-capitalize-words' variable can be customized so that
;; commonly used proper nouns and acronyms are capitalized or upcased,
;; respectively.
;;
;; The `auto-capitalize-yank' option controls whether words in yanked
;; text should by capitalized in the same way.
;;
;; To install auto-capitalize.el, copy it to a `load-path' directory,
;; `M-x byte-compile-file' it, and add this to your
;; site-lisp/default.el or ~/.emacs file:
;; (autoload 'auto-capitalize-mode "auto-capitalize"
;;   "Toggle `auto-capitalize' minor mode in this buffer." t)
;; (autoload 'turn-on-auto-capitalize-mode "auto-capitalize"
;;   "Turn on `auto-capitalize' minor mode in this buffer." t)
;; (autoload 'enable-auto-capitalize-mode "auto-capitalize"
;;   "Enable `auto-capitalize' minor mode in this buffer." t)
;;
;; To turn on (unconditional) capitalization in all Text modes, add
;; this to your site-lisp/default.el or ~/.emacs file:
;; (add-hook 'text-mode-hook 'turn-on-auto-capitalize-mode)
;; To enable (interactive) capitalization in all Text modes, add this
;; to your site-lisp/default.el or ~/.emacs file:
;; (add-hook 'text-mode-hook 'enable-auto-capitalize-mode)
;;
;; To prevent a word from ever being capitalized or upcased
;; (e.g. "http"), simply add it (in lowercase) to the
;; `auto-capitalize-words' list.
;;
;; To prevent a word in the `auto-capitalize-words' list from being
;; capitalized or upcased in a particular context (e.g.
;; "GNU.emacs.sources"), insert the following whitespace or
;; punctuation character with `M-x quoted-insert' (e.g. `gnu C-q .').
;;
;; To enable contractions based on a word in the
;; `auto-capitalize-words' list to be capitalized or upcased
;; (e.g. "I'm") in the middle of a sentence in Text mode, define the
;; apostrophe as a punctuation character or as a symbol that joins two
;; words:
;; ;; Use "_" instead of "." to define apostrophe as a symbol:
;; (modify-syntax-entry ?' ".   " text-mode-syntax-table) ; was "w   "

;;; Some minor changes made by me (after I copied from emacswiki):
;;
;; 1 Apply Emacs 24.3 (due to ‘last-command-char’ -> ‘last-command-event’)
;; 2 Add default predicate function.  It does:
;;   * Only allow auto capitalization after specific character you
;;     typed.  (see ‘auto-capitalize-allowed-chars’)
;;   * Configurable on-and-off in specific buffers
;;     (see ‘auto-capitalize-inhibit-buffers’)
;;   * Work with prog-mode based major-mode.  Only turned on if the
;;     cursor is inside comment or string.
;;   * Added some package specific predicates.
;; 3 fixed some warnings.
;; 4 use of lexical-biding.
;; 5 use capitalized words of aspell’s dictionary
;;   (see ‘auto-capitalize-aspell-file’)
;;
;; Note that I only used this package in Ubuntu and only Emacs (not
;; XEmacs). So I might be wrongly changed something because original
;; version had some XEmacs specific conditions.  (Pull Requests are
;; welcome)
;;

;; Rationale:
;;
;; The implementation of auto-capitalize via an after-change-function is
;; somewhat complicated, but two simpler designs don't work due to
;; quirks in Emacs' implementation itself:
;;
;; One idea is to advise `self-insert-command' to `upcase'
;; `last-command-event' before it is run, but command_loop_1 optimizes
;; out the call to the Lisp binding with its C binding
;; (Fself_insert_command), which prevents any advice from being run.
;;
;; Another idea is to use a before-change-function to `upcase'
;; `last-command-event', but the change functions are called by
;; internal_self_insert, which has already had `last-command-event'
;; passed to it as a C function parameter by command_loop_1.


;; Old emacswiki comments:

;; 1 Jun 2009: It does not work with Aquamacs 1.7/GNUEmacs 22. Only the first word in the buffer
;; (or the first word typed after mode activation) is capitalized.
;; Maybe the code is too old (1998). -- Rikal

;; 29 Aug 2009: Added auto-capitalize-sentence-end which should probably work on older and current day emacsen
;; tested on 23.0.90, please test on your emacs
;; -- dtaht

;; 30 Nov 2010: @Rikal: Are you ending sentences as required (e.g.: with two spaces)? Check "C-h f sentence-end RET".
;; -- elena

;; 6 Sep 2013: Apply SKK package and split functions
;; -- Yuta


(provide 'auto-capitalize)
;;; auto-capitalize.el ends here
