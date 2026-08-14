#!/bin/bash
set -euo pipefail

NODE_VERSION="${NODE_VERSION:-24.18.1}"
DSH_VERSION="${DSH_VERSION:-0.1.0-rc.6}"
RELEASE_TAG="${RELEASE_TAG:?Set RELEASE_TAG to the GitHub release tag}"
OUTPUT_DIR="${1:-dist}"
ARCHITECTURE="arm64"
ASSET_NAME="dsh-runtime-${ARCHITECTURE}.zip"
NODE_ARCHIVE="node-v${NODE_VERSION}-darwin-${ARCHITECTURE}.tar.gz"
NODE_BASE_URL="https://nodejs.org/dist/v${NODE_VERSION}"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
BUILD_ROOT="$(mktemp -d)"
trap 'rm -rf "$BUILD_ROOT"' EXIT

curl --fail --location --retry 3 "$NODE_BASE_URL/$NODE_ARCHIVE" -o "$BUILD_ROOT/$NODE_ARCHIVE"
curl --fail --location --retry 3 "$NODE_BASE_URL/SHASUMS256.txt" -o "$BUILD_ROOT/SHASUMS256.txt"
(
  cd "$BUILD_ROOT"
  expected="$(awk -v file="$NODE_ARCHIVE" '$2 == file {print $1}' SHASUMS256.txt)"
  actual="$(shasum -a 256 "$NODE_ARCHIVE" | awk '{print $1}')"
  test -n "$expected" && test "$expected" = "$actual"
)

tar -xzf "$BUILD_ROOT/$NODE_ARCHIVE" -C "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT/runtime/node" "$BUILD_ROOT/runtime/app"
ditto "$BUILD_ROOT/node-v${NODE_VERSION}-darwin-${ARCHITECTURE}" "$BUILD_ROOT/runtime/node"

"$BUILD_ROOT/runtime/node/bin/npm" install \
  --prefix "$BUILD_ROOT/runtime/app" \
  --omit=dev \
  --no-audit \
  --no-fund \
  "@deepseek-ai/dsh@${DSH_VERSION}"

ARCHIVE_PATH="$OUTPUT_DIR/$ASSET_NAME"
(
  cd "$BUILD_ROOT"
  ditto -c -k --sequesterRsrc --keepParent runtime "$ARCHIVE_PATH"
)

SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
ARCHIVE_SIZE="$(stat -f '%z' "$ARCHIVE_PATH")"
ARCHIVE_URL="https://github.com/fsyabc111/Dsh-MacLauncher/releases/download/${RELEASE_TAG}/${ASSET_NAME}"

MANIFEST_DSH_VERSION="$DSH_VERSION" \
MANIFEST_NODE_VERSION="$NODE_VERSION" \
MANIFEST_ARCHITECTURE="$ARCHITECTURE" \
MANIFEST_ARCHIVE_URL="$ARCHIVE_URL" \
MANIFEST_ARCHIVE_SIZE="$ARCHIVE_SIZE" \
MANIFEST_SHA256="$SHA256" \
"$BUILD_ROOT/runtime/node/bin/node" - "$OUTPUT_DIR/runtime-manifest.json" <<'JS'
const fs = require('fs');
const output = process.argv[2];
fs.writeFileSync(output, JSON.stringify({
  schemaVersion: 1,
  dshVersion: process.env.MANIFEST_DSH_VERSION,
  nodeVersion: process.env.MANIFEST_NODE_VERSION,
  architecture: process.env.MANIFEST_ARCHITECTURE,
  archiveUrl: process.env.MANIFEST_ARCHIVE_URL,
  archiveSize: Number(process.env.MANIFEST_ARCHIVE_SIZE),
  sha256: process.env.MANIFEST_SHA256
}, null, 2) + '\n');
JS

echo "Created $ARCHIVE_PATH and $OUTPUT_DIR/runtime-manifest.json"
