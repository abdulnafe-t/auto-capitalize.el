# Old README, by Yuta Yamada

## auto-capitalize.el

Capitalize char automatically on Emacs.
This package was forked from
[emacswiki](http://www.emacswiki.org/emacs/auto-capitalize.el) for my
daily use.

Some improvements and changes are:

- Recognize programming mode context. Only active auto-capitalize-mode
  inside comment or string if the major-mode was derived from
  `prog-mode`.
- In org-mode, suppress auto-capitalize-mode inside src-block
  (#+begin_src ...)
- Only check after you typed certain characters. You can change this
  behavior by `auto-capitalize-allowed-chars`.
- Improve default predicate function.

#### Installation

If you use el-get you can add recipe to el-get-source following code:

```elisp
    (push '(:name auto-capitalize
            :type github
            :pkgname "yuutayamada/auto-capitalize-el")
           el-get-sources)

And then load this package after execute *M-x el-get-install RET auto-capitalize*

    (require 'auto-capitalize)
```

#### Configuration Examples

```elisp
(setq auto-capitalize-words `("I" "English"))
(add-hook 'after-change-major-mode-hook 'auto-capitalize-mode)
```

or

```
;; This configuration adds capitalized words of .aspell.en.pws
;; (aspell's user dictionary)
(require 'auto-capitalize)
(setq auto-capitalize-words `("I" "English"))
(setq auto-capitalize-aspell-file "path/to/.aspell.en.pws")
(auto-capitalize-setup)
```

# Old package description, by Yuta Yamada

This project was copied from emacswiki page
(https://www.emacswiki.org/emacs/auto-capitalize.el) and I changed
some details. Big difference is this package requires Emacs 24.3 or
higher version.

In `auto-capitalize` minor mode, the first word at the beginning of
a paragraph or sentence (i.e. at `left-margin` on a line following
`paragraph-separate`, after `paragraph-start` at `left-margin`, or
after `sentence-end`) is automatically capitalized when a following
whitespace or punctuation character is inserted.

The `auto-capitalize-words` variable can be customized so that
commonly used proper nouns and acronyms are capitalized or upcased,
respectively.

The `auto-capitalize-yank` option controls whether words in yanked
text should by capitalized in the same way.

To install auto-capitalize.el, copy it to a `load-path` directory,
`M-x byte-compile-file` it, and add this to your
site-lisp/default.el or ~/.emacs file:

```` elisp
(autoload 'auto-capitalize-mode "auto-capitalize"
  "Toggle `auto-capitalize' minor mode in this buffer." t)
(autoload 'turn-on-auto-capitalize-mode "auto-capitalize"
  "Turn on `auto-capitalize' minor mode in this buffer." t)
(autoload 'enable-auto-capitalize-mode "auto-capitalize"
  "Enable `auto-capitalize' minor mode in this buffer." t)
````

To turn on (unconditional) capitalization in all Text modes, add
this to your site-lisp/default.el or ~/.emacs file:

````elisp
(add-hook 'text-mode-hook 'turn-on-auto-capitalize-mode)
````

To enable (interactive) capitalization in all Text modes, add this
to your site-lisp/default.el or ~/.emacs file:

````elisp
(add-hook 'text-mode-hook 'enable-auto-capitalize-mode)
````

To prevent a word from ever being capitalized or upcased
(e.g. "http"), simply add it (in lowercase) to the
`auto-capitalize-words` list.

To prevent a word in the `auto-capitalize-words` list from being
capitalized or upcased in a particular context (e.g.
"GNU.emacs.sources"), insert the following whitespace or
punctuation character with `M-x quoted-insert` (e.g. `gnu C-q .`).

To enable contractions based on a word in the
`auto-capitalize-words` list to be capitalized or upcased
(e.g. "I'm") in the middle of a sentence in Text mode, define the
apostrophe as a punctuation character or as a symbol that joins two
words:

````elisp
;; Use "_" instead of "." to define apostrophe as a symbol:
(modify-syntax-entry ?' ".   " text-mode-syntax-table) ; was "w   "
````

Some minor changes made by me (after I copied from emacswiki):

1. Apply Emacs 24.3 (due to ‘last-command-char’ -> ‘last-command-event’)
2. Add default predicate function.  It does:
  - Only allow auto capitalization after specific character you
    typed.  (see ‘auto-capitalize-allowed-chars’)
  - Configurable on-and-off in specific buffers
    (see ‘auto-capitalize-inhibit-buffers’)
  - Work with prog-mode based major-mode.  Only turned on if the
    cursor is inside comment or string.
  - Added some package specific predicates.
3. fixed some warnings.
4. use of lexical-biding.
5. use capitalized words of aspell’s dictionary (see
   ‘auto-capitalize-aspell-file’)

Note that I only used this package in Ubuntu and only Emacs (not
XEmacs). So I might be wrongly changed something because original
version had some XEmacs specific conditions.  (Pull Requests are
welcome)

## Rationale:

The implementation of auto-capitalize via an after-change-function is
somewhat complicated, but two simpler designs don't work due to
quirks in Emacs' implementation itself:

One idea is to advise `self-insert-command` to `upcase`
`last-command-event` before it is run, but command_loop_1 optimizes
out the call to the Lisp binding with its C binding
(Fself_insert_command), which prevents any advice from being run.

Another idea is to use a before-change-function to `upcase`
`last-command-event`, but the change functions are called by
internal_self_insert, which has already had `last-command-event`
passed to it as a C function parameter by command_loop_1.

## Old emacswiki comments:

1 Jun 2009: It does not work with Aquamacs 1.7/GNUEmacs 22. Only the first word in the buffer
(or the first word typed after mode activation) is capitalized.
Maybe the code is too old (1998). -- Rikal

29 Aug 2009: Added auto-capitalize-sentence-end which should probably work on older and current day emacsen
tested on 23.0.90, please test on your emacs
-- dtaht

30 Nov 2010: @Rikal: Are you ending sentences as required (e.g.: with two spaces)? Check "C-h f sentence-end RET".
-- elena

6 Sep 2013: Apply SKK package and split functions
-- Yuta
