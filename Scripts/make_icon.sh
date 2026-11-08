#!/bin/bash
# Genera Resources/AppIcon.icns disegnando l'icona in modo vettoriale (nessuna
# risorsa raster di terze parti). Richiede il SDK macOS per compilare lo script
# Swift incluso. È idempotente: riscrive sempre l'icns.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="Resources/AppIcon.iconset"
mkdir -p Resources

echo "==> Disegno icona"
PIZZINU_ICONSET="$ICONSET" swift Scripts/make_icon.swift

echo "==> Creazione AppIcon.icns"
iconutil -c icns "$ICONSET" -o "Resources/AppIcon.icns"
rm -rf "$ICONSET"
echo "==> Resources/AppIcon.icns pronto"
