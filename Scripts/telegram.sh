#!/bin/bash
#
# Pubblicazione sul canale Telegram di Pizzinu tramite un bot amministratore.
#
# Il token del bot vive SOLO nel Portachiavi di questo Mac (voce «Pizzinu Telegram bot»):
# mai nel repository, in chat o sulla riga di comando (curl lo legge da stdin).
#
#   bash Scripts/telegram.sh setup              salva il token (incollalo quando richiesto)
#   bash Scripts/telegram.sh check              controlla bot, canale e permessi
#   bash Scripts/telegram.sh preview FILE       mostra il post come verrà inviato
#   bash Scripts/telegram.sh post FILE          pubblica il testo di FILE
#   bash Scripts/telegram.sh file PATH [FILE]   carica un file (es. lo zip) con didascalia
#   bash Scripts/telegram.sh release            post da dist/telegram-<versione>.md + zip
#   bash Scripts/telegram.sh pin ID             fissa in alto il messaggio ID
#
# Formato dei testi: quello di md/TELEGRAM.md — **grassetto**, __corsivo__, `codice`,
# link nudi. Il resto passa così com'è.
# Prima di ogni invio chiede conferma; --yes la salta (solo dopo il sì dell'utente).
# Canale: @pizzinuapp, oppure PIZZINU_TG_CHAT=@altro per le prove.
#
set -euo pipefail
cd "$(dirname "$0")/.."

SERVICE="Pizzinu Telegram bot"
ACCOUNT="piratepxl"
CHAT="${PIZZINU_TG_CHAT:-@pizzinuapp}"
API="https://api.telegram.org"

YES=0
ARGS=()
for a in "$@"; do
  if [ "$a" = "--yes" ]; then YES=1; else ARGS+=("$a"); fi
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

die() { echo "!!  $*" >&2; exit 1; }

read_token() {
  security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w 2>/dev/null \
    || die "Token non trovato nel Portachiavi. Salvalo con: bash Scripts/telegram.sh setup"
}

# api METODO [opzioni curl...] — l'URL con il token passa da stdin, non da argv.
api() {
  local method="$1"; shift
  local out token
  token="$(read_token)" || exit 1
  out="$(printf 'url = "%s/bot%s/%s"\n' "$API" "$token" "$method" \
    | curl -sS --max-time 120 -K - "$@")" || die "Telegram non risponde."
  if [ "$(printf '%s' "$out" | jq -r '.ok')" != "true" ]; then
    die "Telegram: $(printf '%s' "$out" | jq -r '.description // "errore sconosciuto"')"
  fi
  printf '%s' "$out"
}

# Converte il formato dei testi in HTML di Telegram.
to_html() {
  python3 -I -c '
import html, re, sys
t = html.escape(open(sys.argv[1], encoding="utf-8").read().strip(), quote=False)
codes = []
def keep(m):
    codes.append(m.group(1)); return "\x00%d\x00" % (len(codes) - 1)
t = re.sub(r"`([^`\n]+)`", keep, t)
t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t, flags=re.S)
t = re.sub(r"__(.+?)__", r"<i>\1</i>", t, flags=re.S)
t = re.sub(r"\x00(\d+)\x00", lambda m: "<code>%s</code>" % codes[int(m.group(1))], t)
sys.stdout.write(t)
' "$1"
}

confirm() {
  [ "$YES" = 1 ] && return 0
  [ -t 0 ] || die "Serve una conferma: rilancia da Terminale o aggiungi --yes."
  read -r -p "$1 [s/N] " r
  [ "$r" = "s" ] || [ "$r" = "S" ] || die "Annullato."
}

need_file() { [ -f "$1" ] || die "File non trovato: $1"; }

case "${1:-}" in
  setup)
    if security find-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1; then
      die "Il token c'è già. Per cambiarlo: security delete-generic-password -s \"$SERVICE\" -a $ACCOUNT"
    fi
    read -r -s -p "Incolla il token di @BotFather e premi Invio: " TOKEN; echo
    [[ "$TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]] || die "Non sembra un token di bot."
    printf 'url = "%s/bot%s/getMe"\n' "$API" "$TOKEN" | curl -sS -K - | jq -e '.ok' >/dev/null \
      || die "Telegram rifiuta il token."
    security add-generic-password -s "$SERVICE" -a "$ACCOUNT" \
      -l "Pizzinu – bot Telegram" -T /usr/bin/security -w "$TOKEN"
    unset TOKEN
    echo "==> Token salvato nel Portachiavi."
    "$0" check
    ;;
  check)
    ME="$(api getMe)"
    BOT_ID="$(printf '%s' "$ME" | jq -r '.result.id')"
    echo "==> Bot: @$(printf '%s' "$ME" | jq -r '.result.username')"
    CH="$(api getChat --data-urlencode "chat_id=$CHAT")"
    echo "==> Canale: $(printf '%s' "$CH" | jq -r '.result.title') ($CHAT)"
    MEM="$(api getChatMember --data-urlencode "chat_id=$CHAT" --data-urlencode "user_id=$BOT_ID")"
    printf '%s' "$MEM" | jq -r '.result |
      "    ruolo: \(.status)",
      "    pubblica: \(.can_post_messages // false)",
      "    modifica: \(.can_edit_messages // false)",
      "    fissa: \(.can_pin_messages // .can_edit_messages // false)"'
    [ "$(printf '%s' "$MEM" | jq -r '.result.can_post_messages // false')" = "true" ] \
      || die "Il bot non può pubblicare: rendilo amministratore con «Pubblica messaggi»."
    ;;
  preview)
    need_file "${2:?Uso: preview FILE}"
    to_html "$2"; echo
    ;;
  post)
    need_file "${2:?Uso: post FILE}"
    TEXT="$(to_html "$2")"
    [ ${#TEXT} -le 4096 ] || die "Testo troppo lungo (${#TEXT}/4096)."
    printf '%s\n\n' "$TEXT"
    confirm "Pubblico questo post su $CHAT?"
    R="$(api sendMessage --data-urlencode "chat_id=$CHAT" --data-urlencode "text=$TEXT" \
      --data-urlencode "parse_mode=HTML" --data-urlencode "link_preview_options={\"is_disabled\":true}")"
    echo "==> Pubblicato, messaggio $(printf '%s' "$R" | jq -r '.result.message_id')"
    ;;
  file)
    FILE="${2:?Uso: file PATH [FILE_DIDASCALIA]}"
    need_file "$FILE"
    CAPTION=""
    if [ -n "${3:-}" ]; then need_file "$3"; CAPTION="$(to_html "$3")"; fi
    [ ${#CAPTION} -le 1024 ] || die "Didascalia troppo lunga (${#CAPTION}/1024)."
    SIZE="$(stat -f %z "$FILE")"
    [ "$SIZE" -le 52428800 ] || die "File oltre i 50 MB concessi ai bot."
    echo "File: $FILE ($(( SIZE / 1024 )) KB)"
    [ -n "$CAPTION" ] && printf '%s\n' "$CAPTION"
    confirm "Carico questo file su $CHAT?"
    FORM=(-F "chat_id=$CHAT" -F "document=@$FILE")
    [ -n "$CAPTION" ] && FORM+=(--form-string "caption=$CAPTION" -F "parse_mode=HTML")
    R="$(api sendDocument "${FORM[@]}")"
    echo "==> Caricato, messaggio $(printf '%s' "$R" | jq -r '.result.message_id')"
    ;;
  release)
    VERSION=$(sed -n 's/^VERSION="\(.*\)"/\1/p' build.sh)
    NOTES="dist/telegram-${VERSION}.md"
    ZIP="dist/Pizzinu-${VERSION}.zip"
    need_file "$NOTES"; need_file "$ZIP"
    [ -f "dist/Pizzinu.zip.sig" ] || die "Manca dist/Pizzinu.zip.sig: rifai Scripts/package_release.sh."
    printf '%s\n\n' "$(to_html "$NOTES")"
    echo "+ file $ZIP ($(( $(stat -f %z "$ZIP") / 1024 )) KB)"
    confirm "Pubblico l'uscita $VERSION su $CHAT (post + zip)?"
    YES=1
    "$0" post "$NOTES" --yes
    "$0" file "$ZIP" --yes
    ;;
  pin)
    ID="${2:?Uso: pin ID}"
    confirm "Fisso in alto il messaggio $ID su $CHAT?"
    api pinChatMessage --data-urlencode "chat_id=$CHAT" --data-urlencode "message_id=$ID" \
      --data-urlencode "disable_notification=true" >/dev/null
    echo "==> Fissato."
    ;;
  *)
    sed -n '3,19p' "$0"; exit 1
    ;;
esac
