#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

output="${1:?usage: scripts/build-root-helper.sh <output path> [iphoneos]}"
platform="${2:-host}"

mkdir -p "$(dirname "$output")"

sources=(
	RootHelper/main.swift
	Sources/Core/Privileged/RootProtocol.swift
	Sources/Core/FileSystem/FileNode.swift
	Sources/Core/FileSystem/DirectoryLister.swift
	Sources/Core/Remote/RemoteFileProvider.swift
)

if [ "$platform" = "iphoneos" ]; then
	sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
	xcrun --sdk iphoneos swiftc -O -swift-version 5 -sdk "$sdk" -target arm64-apple-ios15.0 -o "$output" "${sources[@]}"
else
	swiftc -O -swift-version 5 -o "$output" "${sources[@]}"
fi
