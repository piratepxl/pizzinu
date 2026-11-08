#!/bin/bash
#
# Chiave di firma degli aggiornamenti di Pizzinu (Ed25519).
#
# La chiave privata vive SOLO nel Portachiavi di questo Mac (voce «Pizzinu update
# signing key»): non va mai nel repository né in chat. L'app contiene la chiave
# pubblica (Updater.swift) e installa soltanto zip firmati con questa chiave.
#
#   bash Scripts/update_key.sh generate     crea la chiave (una volta sola)
#   bash Scripts/update_key.sh public       stampa la chiave pubblica
#   bash Scripts/update_key.sh sign FILE    scrive FILE.sig
#   bash Scripts/update_key.sh export       stampa la chiave privata, per la copia
#                                           di sicurezza nel gestore di password
#   bash Scripts/update_key.sh import       la rimette nel Portachiavi (altro Mac):
#                                           incollala quando richiesto
#
# Se la chiave va persa, le versioni già installate non potranno più
# aggiornarsi da sole: tienine una copia in un posto sicuro.
#
set -euo pipefail
cd "$(dirname "$0")/.."

SERVICE="Pizzinu update signing key"
ACCOUNT="piratepxl"
TOOL="Scripts/update_sign.swift"

if [ -z "${SDKROOT:-}" ]; then
  FALLBACK="$(ls -d "$(xcrun --show-sdk-path)"/../MacOSX2[0-6]*.sdk 2>/dev/null | sort -V | tail -1 || true)"
  [ -n "$FALLBACK" ] && export SDKROOT="$FALLBACK"
fi

swift_tool() { swift "$TOOL" "$@"; }

read_key() {
  security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w 2>/dev/null \
    || { echo "!!  Chiave non trovata nel Portachiavi. Creala con: bash Scripts/update_key.sh generate (o import)" >&2; exit 1; }
}

case "${1:-}" in
  generate)
    if security find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1; then
      echo "!!  La chiave esiste già: non la sovrascrivo." >&2; exit 1
    fi
    KEY="$(swift_tool generate)"
    security add-generic-password -s "$SERVICE" -a "$ACCOUNT" \
      -l "Pizzinu – chiave di firma degli aggiornamenti" -T /usr/bin/security -w "$KEY"
    unset KEY
    echo "==> Chiave creata nel Portachiavi. Chiave pubblica da mettere in Updater.swift:"
    read_key | swift_tool public
    ;;
  public)
    read_key | swift_tool public
    ;;
  sign)
    FILE="${2:?Uso: sign FILE}"
    read_key | swift_tool sign "$FILE" > "$FILE.sig"
    echo "==> $FILE.sig"
    ;;
  export)
    echo "Chiave privata (copiala nel gestore di password, poi chiudi il Terminale):" >&2
    read_key
    ;;
  import)
    if security find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1; then
      echo "!!  Su questo Mac la chiave c'è già." >&2; exit 1
    fi
    read -r -s -p "Incolla la chiave privata e premi Invio: " KEY; echo
    printf '%s' "$KEY" | swift_tool public >/dev/null || { echo "!!  Chiave non valida." >&2; exit 1; }
    security add-generic-password -s "$SERVICE" -a "$ACCOUNT" \
      -l "Pizzinu – chiave di firma degli aggiornamenti" -T /usr/bin/security -w "$KEY"
    unset KEY
    echo "==> Chiave importata. Chiave pubblica:"
    read_key | swift_tool public
    ;;
  *)
    sed -n '3,20p' "$0"; exit 1
    ;;
esac
