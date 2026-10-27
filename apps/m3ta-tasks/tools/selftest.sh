#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.th3m3taway.m3tatasks.savedState
store=/tmp/M3taTasks-self.store
rm -f $store $store-shm $store-wal
APP_STORE=$store ~/Applications/M3taTasks.app/Contents/MacOS/M3taTasks --selftest
