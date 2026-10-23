#!/bin/bash
set -euo pipefail

helper="${1:?usage: scripts/test-root-helper.sh <helper binary>}"
helper="$(cd "$(dirname "$helper")" && pwd)/$(basename "$helper")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

json() {
	python3 -c "import json, sys; data = json.load(sys.stdin); $1"
}

expect_failure() {
	local code="$1"
	shift
	local errors
	if errors="$("$@" 2>&1 >/dev/null </dev/null)"; then
		fail "expected failure: $*"
	fi
	echo "$errors" | json "assert data['code'] == $code, data" || fail "wrong error code for: $*"
}

"$helper" ping | grep -Eq '^uid=[0-9]+$' || fail "ping"

"$helper" mkdir "$work/a/b/c"
[ -d "$work/a/b/c" ] || fail "mkdir creates intermediate directories"
expect_failure 17 "$helper" mkdir "$work/a"

printf 'hello' | "$helper" write "$work/a/file.txt" new
[ "$(cat "$work/a/file.txt")" = "hello" ] || fail "write new"
expect_failure 17 "$helper" write "$work/a/file.txt" new
printf 'replaced' | "$helper" write "$work/a/file.txt"
[ "$("$helper" read "$work/a/file.txt")" = "replaced" ] || fail "write replace and read"
printf '' | "$helper" write "$work/a/file.txt"
[ ! -s "$work/a/file.txt" ] || fail "write empty replaces contents"
ls -A "$work/a" | grep -q 'filzer-write' && fail "temporary write file left behind"

head -c 5000000 /dev/urandom >"$work/big.bin"
"$helper" write "$work/big-copy.bin" new <"$work/big.bin"
cmp "$work/big.bin" "$work/big-copy.bin" || fail "large write"
"$helper" read "$work/big.bin" | cmp - "$work/big.bin" || fail "large read"
expect_failure 2 "$helper" read "$work/missing"

mkdir "$work/listing"
touch "$work/listing/visible" "$work/listing/.hidden"
mkdir "$work/listing/folder"
"$helper" list "$work/listing" 0 | json "assert sorted(n['name'] for n in data) == ['folder', 'visible'], data" || fail "list hides hidden files"
"$helper" list "$work/listing" 1 | json "assert sorted(n['name'] for n in data) == ['.hidden', 'folder', 'visible'], data" || fail "list shows hidden files"
"$helper" list "$work/listing" 0 | json "assert {n['name']: n['kind'] for n in data} == {'folder': 'directory', 'visible': 'file'}, data" || fail "list kinds"
expect_failure 2 "$helper" list "$work/missing" 0

ln -s "$work/listing" "$work/link"
"$helper" stat "$work/link" | json "assert data['kind'] == 'symlink' and data['symbolicLinkTargetIsDirectory'], data" || fail "stat symlink"
"$helper" stat "$work/listing/folder" | json "assert data['kind'] == 'directory' and data['name'] == 'folder', data" || fail "stat directory"
expect_failure 2 "$helper" stat "$work/missing"

"$helper" symlink "$work/made-link" "$work/listing"
[ -L "$work/made-link" ] || fail "symlink"
expect_failure 17 "$helper" symlink "$work/made-link" "$work/listing"
"$helper" hardlink "$work/hard" "$work/listing/visible"
[ "$(ls -i "$work/hard" | awk '{print $1}')" = "$(ls -i "$work/listing/visible" | awk '{print $1}')" ] || fail "hardlink"

"$helper" copy "$work/a" "$work/a-copy"
cmp "$work/a/file.txt" "$work/a-copy/file.txt" || fail "copy directory"
[ -d "$work/a-copy/b/c" ] || fail "copy keeps nested directories"
expect_failure 17 "$helper" copy "$work/a" "$work/a-copy"

"$helper" move "$work/a-copy" "$work/a-moved"
[ -d "$work/a-moved" ] && [ ! -e "$work/a-copy" ] || fail "move"
expect_failure 17 "$helper" move "$work/a-moved" "$work/a"

printf 'x' >"$work/mode.txt"
"$helper" chmod 420 "$work/mode.txt" 0
"$helper" stat "$work/mode.txt" | json "assert data['posixPermissions'] == 420, data" || fail "chmod"
mkdir "$work/modetree"
touch "$work/modetree/inner"
"$helper" chmod 493 "$work/modetree" 1
"$helper" stat "$work/modetree/inner" | json "assert data['posixPermissions'] == 493, data" || fail "recursive chmod"
expect_failure 22 "$helper" chmod notanumber "$work/mode.txt" 0

mkdir "$work/sized"
mkdir "$work/sized/nested"
printf '0123456789' >"$work/sized/ten"
printf '01234567890123456789' >"$work/sized/nested/twenty"
[ "$("$helper" size "$work/sized")" = "30" ] || fail "size"
expect_failure 2 "$helper" size "$work/missing"

"$helper" remove "$work/sized"
[ ! -e "$work/sized" ] || fail "remove directory"
expect_failure 2 "$helper" remove "$work/sized"

expect_failure 22 "$helper" nonsense
expect_failure 22 "$helper" read

echo "root helper tests passed"
