#!/bin/bash
#
# Builds Pizzinu and packs it for a GitHub release:
#   dist/Pizzinu-<version>.zip, dist/Pizzinu-<version>.zip.sha256 and dist/Pizzinu.zip
#   (upload all three to the GitHub release: the website links to Pizzinu.zip)
#
# Usage: bash Scripts/package_release.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^VERSION="\(.*\)"/\1/p' build.sh)
bash build.sh

mkdir -p dist
ZIP="dist/Pizzinu-${VERSION}.zip"
rm -f "$ZIP" "$ZIP.sha256"
# ditto keeps the bundle structure and the ad-hoc signature intact.
ditto -c -k --sequesterRsrc --keepParent build/Pizzinu.app "$ZIP"
(cd dist && shasum -a 256 "Pizzinu-${VERSION}.zip" > "Pizzinu-${VERSION}.zip.sha256")
# Copia con nome fisso: il sito scarica .../releases/latest/download/Pizzinu.zip
cp "$ZIP" dist/Pizzinu.zip

echo "==> $ZIP"
cat "$ZIP.sha256"
