#!/bin/bash
#
# Builds Pizzinu and packs it for a GitHub release:
#   dist/Pizzinu-<version>.zip, dist/Pizzinu-<version>.zip.sha256 and dist/Pizzinu.zip
#   and dist/Pizzinu.zip.sig (Ed25519 signature, see Scripts/update_key.sh).
#   Upload all four to the GitHub release: the website links to Pizzinu.zip and
#   the app updates itself only from a signed Pizzinu.zip.
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
# Firma Ed25519 per l'aggiornamento automatico (chiave nel Portachiavi).
bash Scripts/update_key.sh sign dist/Pizzinu.zip
PUB="$(grep -o 'publicKey = "[^"]*"' Sources/Pizzinu/Updater.swift | cut -d'"' -f2)"
if [ "$(bash Scripts/update_key.sh public)" != "$PUB" ]; then
  echo "!!  La chiave del Portachiavi non corrisponde a quella dentro l'app." >&2; exit 1
fi
echo "==> Carica nella release: $ZIP, $ZIP.sha256, dist/Pizzinu.zip, dist/Pizzinu.zip.sig"

echo "==> $ZIP"
cat "$ZIP.sha256"
