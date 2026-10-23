#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

printf 'RootHelperTool.run(Array(CommandLine.arguments.dropFirst()))\n' >"$work/main.swift"
swiftc -O -swift-version 5 -o "$work/helper" "$work/main.swift" \
	"$repo/Sources/Core/Privileged/RootHelperTool.swift" \
	"$repo/Sources/Core/FileSystem/FileNode.swift" \
	"$repo/Sources/Core/FileSystem/DirectoryLister.swift" \
	"$repo/Sources/Core/Remote/RemoteFileProvider.swift"

helper="$work/helper"
files="$work/files"
mkdir "$files"

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

"$helper" mkdir "$files/a/b/c" | json "assert data['kind'] == 'directory' and data['name'] == 'c', data" || fail "mkdir result"
[ -d "$files/a/b/c" ] || fail "mkdir creates intermediate directories"
expect_failure 17 "$helper" mkdir "$files/a"

printf 'hello' | "$helper" write "$files/a/file.txt" new | json "assert data['kind'] == 'file' and data['size'] == 5, data" || fail "write new result"
[ "$(cat "$files/a/file.txt")" = "hello" ] || fail "write new"
expect_failure 17 "$helper" write "$files/a/file.txt" new
printf 'replaced' | "$helper" write "$files/a/file.txt"
[ "$("$helper" read "$files/a/file.txt")" = "replaced" ] || fail "write replace and read"
printf '' | "$helper" write "$files/a/file.txt"
[ ! -s "$files/a/file.txt" ] || fail "write empty replaces contents"
ls -A "$files/a" | grep -q 'filzer-write' && fail "temporary write file left behind"

head -c 5000000 /dev/urandom >"$work/big.bin"
"$helper" write "$files/big-copy.bin" new <"$work/big.bin" >/dev/null
cmp "$work/big.bin" "$files/big-copy.bin" || fail "large write"
"$helper" read "$work/big.bin" | cmp - "$work/big.bin" || fail "large read"
expect_failure 2 "$helper" read "$files/missing"

mkdir "$files/listing"
touch "$files/listing/visible" "$files/listing/.hidden"
mkdir "$files/listing/folder"
"$helper" list "$files/listing" 0 | json "assert sorted(n['name'] for n in data) == ['folder', 'visible'], data" || fail "list hides hidden files"
"$helper" list "$files/listing" 1 | json "assert sorted(n['name'] for n in data) == ['.hidden', 'folder', 'visible'], data" || fail "list shows hidden files"
"$helper" list "$files/listing" 0 | json "assert {n['name']: n['kind'] for n in data} == {'folder': 'directory', 'visible': 'file'}, data" || fail "list kinds"
expect_failure 2 "$helper" list "$files/missing" 0

ln -s "$files/listing" "$files/link"
"$helper" stat "$files/link" | json "assert data['kind'] == 'symlink' and data['symbolicLinkTargetIsDirectory'], data" || fail "stat symlink"
"$helper" stat "$files/listing/folder" | json "assert data['kind'] == 'directory' and data['name'] == 'folder', data" || fail "stat directory"
expect_failure 2 "$helper" stat "$files/missing"

"$helper" symlink "$files/made-link" "$files/listing" | json "assert data['kind'] == 'symlink', data" || fail "symlink result"
[ -L "$files/made-link" ] || fail "symlink"
expect_failure 17 "$helper" symlink "$files/made-link" "$files/listing"
"$helper" hardlink "$files/hard" "$files/listing/visible" | json "assert data['kind'] == 'file', data" || fail "hardlink result"
[ "$(ls -i "$files/hard" | awk '{print $1}')" = "$(ls -i "$files/listing/visible" | awk '{print $1}')" ] || fail "hardlink"

"$helper" copy "$files/a" "$files/a-copy" | json "assert data['kind'] == 'directory' and data['name'] == 'a-copy', data" || fail "copy result"
cmp "$files/a/file.txt" "$files/a-copy/file.txt" || fail "copy directory"
[ -d "$files/a-copy/b/c" ] || fail "copy keeps nested directories"
expect_failure 17 "$helper" copy "$files/a" "$files/a-copy"

"$helper" move "$files/a-copy" "$files/a-moved" | json "assert data['name'] == 'a-moved', data" || fail "move result"
[ -d "$files/a-moved" ] && [ ! -e "$files/a-copy" ] || fail "move"
expect_failure 17 "$helper" move "$files/a-moved" "$files/a"

printf 'x' >"$files/mode.txt"
"$helper" chmod 420 "$files/mode.txt" 0
"$helper" stat "$files/mode.txt" | json "assert data['posixPermissions'] == 420, data" || fail "chmod"
mkdir "$files/modetree"
touch "$files/modetree/inner"
"$helper" chmod 493 "$files/modetree" 1
"$helper" stat "$files/modetree/inner" | json "assert data['posixPermissions'] == 493, data" || fail "recursive chmod"
expect_failure 22 "$helper" chmod notanumber "$files/mode.txt" 0

mkdir "$files/sized"
mkdir "$files/sized/nested"
printf '0123456789' >"$files/sized/ten"
printf '01234567890123456789' >"$files/sized/nested/twenty"
[ "$("$helper" size "$files/sized")" = "30" ] || fail "size"
expect_failure 2 "$helper" size "$files/missing"

"$helper" remove "$files/sized"
[ ! -e "$files/sized" ] || fail "remove directory"
expect_failure 2 "$helper" remove "$files/sized"

expect_failure 22 "$helper" nonsense
expect_failure 22 "$helper" read

echo "root helper tests passed"
