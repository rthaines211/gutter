#!/bin/zsh
# Move the codesigning identity into a dedicated keychain that `make unlock`
# opens with a password from Makefile.local, so any session (SSH, Claude, a
# fresh boot) can build with no prompt. The login keychain stays untouched.
#
# Run once, in a session where the login keychain is unlocked:
#   scripts/setup-build-keychain.sh [path/to/Makefile.local]
# Re-run after the certificate is reissued (delete build.keychain-db first).
set -euo pipefail

KC=$HOME/Library/Keychains/build.keychain-db
LOCAL=${1:-$HOME/projects/gutter/Makefile.local}
PASS=$(openssl rand -hex 16)
P12PASS=$(openssl rand -hex 16)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

security export -k login.keychain-db -t identities -f pkcs12 -P "$P12PASS" -o "$TMP/id.p12"
security create-keychain -p "$PASS" "$KC"
security set-keychain-settings "$KC"  # no auto-lock, no lock on sleep
security unlock-keychain -p "$PASS" "$KC"
security import "$TMP/id.p12" -k "$KC" -P "$P12PASS" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null
# First in the search list, so codesign finds the identity here and not in the
# (possibly locked) login keychain.
security list-keychains -d user -s "$KC" ${(f)"$(security list-keychains -d user | tr -d ' "' | grep -v build.keychain)"}

printf '\n## Dedicated signing keychain (scripts/setup-build-keychain.sh).\nKEYCHAIN = %s\nBUILD_KEYCHAIN_PASS = %s\n' "$KC" "$PASS" >> "$LOCAL"
security find-identity -v -p codesigning "$KC"
echo "Done. Wrote KEYCHAIN and BUILD_KEYCHAIN_PASS to $LOCAL"
