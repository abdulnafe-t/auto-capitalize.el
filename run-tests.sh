#!/bin/sh
set -eu

EMACS=${EMACS:-emacs}
AUCTEX_DIR=$(find ~/.config/emacs/elpa -type d -name 'auctex-*' 2>/dev/null | sort | tail -n 1)

run_tests() {
  exec "$EMACS" --batch "$@" -l test/auto-capitalize-tests.el \
    -f ert-run-tests-batch-and-exit
}

if [ -n "$AUCTEX_DIR" ]; then
  run_tests -L . -L "$AUCTEX_DIR" --eval "(require 'tex)"
else
  run_tests -L .
fi
