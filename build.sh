#!/bin/bash
# Costruisce Pizzinu.app in ./build. Usa --install per copiarla anche in /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Pizzinu"
BUNDLE_ID="it.pizzinu.app"
VERSION="1.3.0"
OUT="build/${APP_NAME}.app"
CONFIG="${CONFIG:-release}"

# La cartella del progetto può contenere spazi (per esempio un percorso
# Nextcloud): SwiftDriver non legge correttamente i file di dipendenza quando
# la cartella di compilazione ne contiene. La cartella intermedia viene quindi
# tenuta fuori dal progetto, in una posizione senza spazi.
SCRATCH="${PIZZINU_SCRATCH:-${TMPDIR:-/tmp/}}"
SCRATCH="${SCRATCH%/}/pizzinu-build-${CONFIG}"

# Il SDK macOS 27 espone SwiftUI `@State` come macro esterna; il plugin
# (SwiftUIMacros) è distribuito solo con Xcode. Con i soli Command Line Tools
# si ripiega sul più recente SDK precedente disponibile.
if [ -z "${SDKROOT:-}" ]; then
  SWIFT_BIN="$(xcrun --find swift)"
  TOOLCHAIN="$(dirname "$(dirname "$SWIFT_BIN")")"
  if ! ls "$TOOLCHAIN"/lib/swift/host/plugins/*SwiftUIMacros* >/dev/null 2>&1; then
    FALLBACK="$(ls -d "$(xcrun --show-sdk-path)"/../MacOSX2[0-6]*.sdk 2>/dev/null | sort -V | tail -1 || true)"
    if [ -n "$FALLBACK" ]; then
      export SDKROOT="$FALLBACK"
      echo "==> Plugin SwiftUIMacros assente: uso $(basename "$SDKROOT")"
    else
      echo "!!  Plugin SwiftUIMacros assente e nessun SDK precedente disponibile." >&2
    fi
  fi
fi

echo "==> Compilazione (${CONFIG})"
swift build -c "${CONFIG}" --scratch-path "${SCRATCH}"

BIN_DIR="$(swift build -c "${CONFIG}" --scratch-path "${SCRATCH}" --show-bin-path)"

echo "==> Generazione icona"
if [ -x "Scripts/make_icon.sh" ]; then
  ./Scripts/make_icon.sh
fi

# Il bundle viene assemblato e firmato in una cartella di passaggio fuori dal
# progetto. Se il progetto vive in una cartella sincronizzata (Nextcloud,
# iCloud Drive) il gestore dei file riapplica di continuo attributi estesi come
# `com.apple.FinderInfo`, che impediscono la firma del codice. Nella cartella di
# passaggio la firma riesce; il bundle firmato viene poi copiato in ./build.
STAGE="${TMPDIR:-/tmp/}pizzinu-stage-${CONFIG}/${APP_NAME}.app"

echo "==> Assemblaggio ${APP_NAME}.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "$STAGE/Contents/MacOS/${APP_NAME}"

if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"
  ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
  ICON_KEY=""
fi

# Puntina delle note fissate in primo piano.
for image in Pin.png AppIconMark.png; do
  if [ -f "Resources/$image" ]; then cp "Resources/$image" "$STAGE/Contents/Resources/$image"; fi
done

# Lingue dell'interfaccia (italiano e inglese): vedi PizzinuKit/Localization.swift.
for lproj in Resources/*.lproj; do
  if [ -d "$lproj" ]; then cp -R "$lproj" "$STAGE/Contents/Resources/"; fi
done

# Caratteri delle note: quelli della cartella Fonts del progetto entrano nel
# bundle. L'applicazione li legge anche da cartelle esterne (vedi FontLibrary).
if [ -d "Fonts" ]; then
  mkdir -p "$STAGE/Contents/Resources/Fonts"
  for font in Fonts/*.ttf Fonts/*.otf Fonts/*.ttc; do
    if [ -f "$font" ]; then cp "$font" "$STAGE/Contents/Resources/Fonts/"; fi
  done
  # Licenze dei caratteri (SIL Open Font License): viaggiano con l'app.
  if [ -d "Fonts/licenses" ]; then cp -R "Fonts/licenses" "$STAGE/Contents/Resources/Fonts/"; fi
fi

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key><string>${APP_NAME}</string>
	<key>CFBundleExecutable</key><string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>CFBundleVersion</key><string>${VERSION}</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSSupportsAutomaticTermination</key><false/>
	<key>NSSupportsSuddenTermination</key><false/>
	<key>CFBundleLocalizations</key><array><string>it</string><string>en</string></array>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	${ICON_KEY}
</dict>
</plist>
PLIST

# Firma ad-hoc, dal più interno al più esterno: prima l'estensione (con il
# ed eventualmente altri componenti, poi l'app.
# Gli attributi estesi vengono rimossi prima della firma: in una cartella
# sincronizzata (Nextcloud, iCloud Drive) possono comparire `com.apple.FinderInfo`
# e simili, che invalidano la verifica della firma.
xattr -cr "$STAGE" 2>/dev/null || true

if [ -f "Packaging/Pizzinu.entitlements" ]; then
  codesign --force --sign - --entitlements "Packaging/Pizzinu.entitlements" "$STAGE" 2>/dev/null \
    || echo "    (firma saltata)"
else
  codesign --force --sign - "$STAGE" 2>/dev/null || echo "    (firma saltata)"
fi

# Il bundle è firmato nella cartella di passaggio: ora viene copiato in ./build.
echo "==> Copia in $OUT"
rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
cp -R "$STAGE" "$OUT"
xattr -cr "$OUT" 2>/dev/null || true

echo "==> Costruita $OUT"

if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "$OUT" "/Applications/${APP_NAME}.app"
  echo "==> Installata in /Applications/${APP_NAME}.app"
fi
