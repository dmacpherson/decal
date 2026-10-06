# shellcheck shell=bash
# decal's logo for the terminal: the penguin sticker, row by row in the logo's teal-to-purple gradient (256 colours).
# install.sh and usb/start.sh keep a copy of the block between the markers (they run before decal exists); the tests
# check the copies are the same.
# --- logo ---
DECAL_LOGO=('   ▄█████▄   ' '  ██▄███▄██  ' '  ███▀ ▀███  ' ' ██▀     ▀██ ' '██         ██' ' ▀█▄▄▄▄▄▄▄█▀ ')
DECAL_LOGO_COLORS=(44 38 33 63 99 135)
# logo_print FD [TEXT...] : the logo on FD (1 or 2), each TEXT beside a row from the second on; in colour only on a
# terminal that has it (NO_COLOR turns it off)
logo_print() {
  local fd=$1 i on="" off="" text=("${@:2}")
  for ((i = 0; i < ${#DECAL_LOGO[@]}; i++)); do
    if [[ -t $fd && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then on=$'\e[1;38;5;'"${DECAL_LOGO_COLORS[i]}m"; off=$'\e[0m'; fi
    printf '%s%s%s%s\n' "$on" "${DECAL_LOGO[i]}" "$off" "$( (( i >= 1 )) && [[ -n ${text[i - 1]:-} ]] && printf '  %s' "${text[i - 1]}")" >&"$fd"
  done
}
# --- end logo ---
