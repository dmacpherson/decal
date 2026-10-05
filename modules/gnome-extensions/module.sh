# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile (P_*)
MODULE_DESC="GNOME extensions (install from extensions.gnome.org, enable, settings, panel logo)"
VENDORED_MAIN="#deddda"              # fill that gets recoloured to P_logo_color (the bundled GNOME logo uses it;
                                     # so should a profile's own `logo` SVG)
ICON_DIR="$HOME/.local/share/decal/icons"
_logo_src() { if [[ -n $P_logo ]]; then echo "$P_logo"; else echo icons/gnome-logo.svg; fi; }   # decal runs modules from their own folder
_logo_path() {   # colour in the file name: GNOME caches icons by path
  if [[ -n $P_logo ]]; then local b; b=$(basename "$P_logo"); echo "$ICON_DIR/logo-${b%.*}-${P_logo_color#\#}.svg"
  else echo "$ICON_DIR/gnome-logo-${P_logo_color#\#}.svg"; fi
}
_uuids() { if (( ${#P_enable[@]} )); then printf '%s\n' "${P_enable[@]}"; fi; }
INSTALLED="$LS_USER_STATE/gnome-extensions.installed"
# config files some extensions keep outside dconf (e.g. Burn My Windows profiles): [gnome-extensions.files]
# maps a path under ~/.config to a file in the profile; a file that was already there is backed up and put back
FILES_REC="$LS_USER_STATE/gnome-extensions.files"
FILES_BK="$LS_USER_STATE/gnome-extensions-files"
_cfg() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/$1"; }
_file_restore() {
  local d=$1 t; t=$(_cfg "$d")
  if [[ -e $FILES_BK/$d ]]; then mv "$FILES_BK/$d" "$t"; else rm -f "$t"; fi
  grep -vxF "$d" "$FILES_REC" > "$FILES_REC.t" || true; mv "$FILES_REC.t" "$FILES_REC"
}
_files_apply() {
  local d t
  if [[ -r $FILES_REC ]]; then
    while IFS= read -r d; do if [[ -n $d && -z ${P_files[$d]+x} ]]; then _file_restore "$d"; fi; done < <(cat "$FILES_REC")
  fi
  for d in "${!P_files[@]}"; do
    t=$(_cfg "$d")
    inside "$(_cfg "")" "$t" || die "files: $d isn't inside ${XDG_CONFIG_HOME:-$HOME/.config}"
    if ! grep -qxF "$d" "$FILES_REC" 2>/dev/null; then
      if [[ -e $t ]]; then mkdir -p "$(dirname "$FILES_BK/$d")"; cp -a "$t" "$FILES_BK/$d"; fi
      echo "$d" >> "$FILES_REC"
    fi
    mkdir -p "$(dirname "$t")"; install -m 600 "${P_files[$d]}" "$t"
  done
}
# Decal Tweaks' "Apps too" block out of GTK's user stylesheets when decal removes the extension (switched off in a
# running Shell, the extension takes it out itself). Same markers as its tweaks/accent-css.js; a file left empty goes.
_strip_app_accent() {
  local f
  for f in "${XDG_CONFIG_HOME:-$HOME/.config}"/gtk-{4,3}.0/gtk.css; do
    [[ -f $f ]] || continue
    python3 - "$f" <<'EOF'
import os, shutil, sys
p = sys.argv[1]; text = open(p).read(); kept = []; inside = False
for line in text.split('\n'):
    if not inside and line.startswith('/* decal accent: begin'): inside = True
    elif inside and line.startswith('/* decal accent: end'): inside = False
    elif not inside: kept.append(line)
rest = '\n'.join(kept).rstrip()
new = rest + '\n' if rest else ''
if new != text:
    if new: open(p + '.decal-new', 'w').write(new); shutil.copymode(p, p + '.decal-new'); os.replace(p + '.decal-new', p)
    else: os.remove(p)
EOF
  done
}
# extensions decal installed that are no longer in the profile: disabled and uninstalled
_drop_unlisted() {
  [[ -r $INSTALLED ]] || return 0
  local u keep=""
  while IFS= read -r u; do
    [[ -n $u ]] || continue
    if _uuids | grep -qxF "$u"; then keep+="$u"$'\n'
    else step "removing $u (no longer in the profile)"; gnome-extensions disable "$u" 2>/dev/null || true; gnome-extensions uninstall "$u" || true; rm -rf "${EXT_HOME:?}/$u"
      [[ $u != decal@decal ]] || _strip_app_accent; fi
  done < <(cat "$INSTALLED")
  printf '%s' "$keep" > "$INSTALLED"
}
# disable: extensions kept off (also ones the distro turns on); each one's previous state is recorded
DISABLED="$LS_USER_STATE/gnome-extensions.disabled"   # "<uuid> on|off": its state before decal turned it off
_ext_lists() {  # _ext_lists UUID on|off : put UUID in enabled-extensions (on) or disabled-extensions (off)
  local en dis; en=$(gsettings get org.gnome.shell enabled-extensions); dis=$(gsettings get org.gnome.shell disabled-extensions)
  read -r en dis < <(python3 -c '
import ast,sys
def lst(v): return [] if v.startswith("@as") else ast.literal_eval(v)
u,want,en,dis=sys.argv[1],sys.argv[2],lst(sys.argv[3]),lst(sys.argv[4])
en=[x for x in en if x!=u]; dis=[x for x in dis if x!=u]
(en if want=="on" else dis).append(u)
print(repr(en).replace(" ",""), repr(dis).replace(" ",""))' "$1" "$2" "$en" "$dis")
  gsettings set org.gnome.shell enabled-extensions "$en"; gsettings set org.gnome.shell disabled-extensions "$dis"
}
_is_on() { gsettings get org.gnome.shell enabled-extensions | grep -qF "'$1'"; }
_disable_apply() {
  local u st keep=""
  if [[ -r $DISABLED ]]; then   # left the disable list: back to how it was
    while read -r u st; do
      [[ -n $u ]] || continue
      if (( ${#P_disable[@]} )) && printf '%s\n' "${P_disable[@]}" | grep -qxF "$u"; then keep+="$u $st"$'\n'
      elif [[ $st == on ]]; then _ext_lists "$u" on; fi
    done < <(cat "$DISABLED")
  fi
  printf '%s' "$keep" > "$DISABLED"
  for u in "${P_disable[@]}"; do
    grep -q "^$u " "$DISABLED" || echo "$u $(_is_on "$u" && echo on || echo off)" >> "$DISABLED"
    _ext_lists "$u" off
  done
}
_disable_undo() {
  [[ -r $DISABLED ]] || return 0
  local u st; while read -r u st; do if [[ -n $u && $st == on ]]; then _ext_lists "$u" on; fi; done < "$DISABLED"
  rm -f "$DISABLED"
}
_dt() { python3 "$LS_REPO/lib/dconf_tool.py" "$@"; }
_settings() {  # _settings CMD [args] : run dconf_tool on the profile's extension settings (if any)
  (( ${#P_file[@]} )) || return 0
  local f ini=(); for f in "${P_file[@]}"; do ini+=(--ini "$f"); done   # several files: in order, a later one wins
  _dt "$1" --base /org/gnome/shell/extensions/ "${ini[@]}" --extensions \
    --prev "$LS_USER_STATE/gnome-extensions.prev.json" --subst "@HOME@=$HOME" --subst "@LOGO_PATH@=$(_logo_path)" --subst "@TERMINAL_CMD@=$(terminal_cmd)" "${@:2}"
}
# known to the running shell, or installed but waiting for the next login (the shell only scans at login)
_loaded() { gnome-extensions info "$1" >/dev/null 2>&1; }
_on_disk() { [[ -d ${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$1 ]]; }
_present() { _loaded "$1" || _on_disk "$1"; }
# extensions that ship with decal ($BUNDLED/<uuid>, none yet): copied in and kept in sync with decal's copy
BUNDLED="${DECAL_BUNDLED_DIR:-bundled}"
EXT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"
_bundled() { safe_name "$1" && [[ -d $BUNDLED/$1 ]]; }
_install_bundled() {  # UUID -> 0 if (re)installed, 1 if already up to date
  local u=$1 d="$EXT_HOME/$1"
  safe_name "$u" || die "not an extension UUID: $u"
  if [[ -d $d ]] && diff -rq --exclude=gschemas.compiled "$BUNDLED/$u" "$d" >/dev/null 2>&1; then return 1; fi
  rm -rf "$d"; mkdir -p "$EXT_HOME"; cp -r "$BUNDLED/$u" "$d"
  if [[ -d $d/schemas ]]; then glib-compile-schemas "$d/schemas"; fi
  return 0
}
_shell_major() { gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1; }

_install_from_ego() {  # UUID -> 0 installed, 1 unavailable
  local uuid=$1 major url tmp; major=$(_shell_major)
  url=$(curl -fsS --proto =https --proto-redir =https "$P_source/extension-info/?uuid=$uuid&shell_version=$major" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["download_url"])' 2>/dev/null) || return 1
  tmp=$(mktemp --suffix=.zip)
  curl -fsSL --proto =https --proto-redir =https "$P_source$url" -o "$tmp" || { rm -f "$tmp"; return 1; }
  gnome-extensions install --force "$tmp"; rm -f "$tmp"
}

module_add() {
  have gnome-extensions || die "gnome-extensions not found (GNOME Shell required)"
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] would install missing: $(for u in $(_uuids); do _present "$u" || printf '%s ' "$u"; done)"; return 0; fi
  local x; for x in "${P_disable[@]}"; do
    if _uuids | grep -qxF "$x"; then die "$x is in both enable and disable in [gnome-extensions]"; fi
  done
  mkdir -p "$LS_USER_STATE" "$ICON_DIR"
  _drop_unlisted
  local u new=0
  for u in $(_uuids); do
    if _bundled "$u"; then
      if _install_bundled "$u"; then new=1; fi
      grep -qxF "$u" "$INSTALLED" 2>/dev/null || echo "$u" >> "$INSTALLED"   # decal's own: always decal's to remove
      continue
    fi
    _present "$u" && continue
    if _install_from_ego "$u"; then
      grep -qxF "$u" "$LS_USER_STATE/gnome-extensions.installed" 2>/dev/null || echo "$u" >> "$LS_USER_STATE/gnome-extensions.installed"; new=1
    else warn "$u is not available on $P_source for GNOME $(_shell_major); skipped"; fi
  done
  # panel logo (colour in the filename: GNOME caches icons by path)
  sed "s/fill:$VENDORED_MAIN/fill:$P_logo_color/g" "$(_logo_src)" > "$(_logo_path)"
  find "$ICON_DIR" -maxdepth 1 \( -name 'gnome-logo-*.svg' -o -name 'logo-*.svg' \) ! -name "$(basename "$(_logo_path)")" -delete
  # enabled-extensions: merge ours in; take ours out of disabled-extensions
  local ini; ini=$(mktemp)
  printf '[org/gnome/shell]\nenabled-extensions=%s\n' "$(_uuids | python3 -c 'import sys; print([l.strip() for l in sys.stdin if l.strip()])')" > "$ini"
  _dt apply --base / --ini "$ini" --prev "$LS_USER_STATE/gnome-extensions-enabled.prev.json" --merge /org/gnome/shell/enabled-extensions
  rm -f "$ini"
  local dis; dis=$(gsettings get org.gnome.shell disabled-extensions)
  for u in $(_uuids); do
    if [[ $dis == *"'$u'"* ]]; then echo "$u" >> "$LS_USER_STATE/gnome-extensions.undisabled"; fi
  done
  if [[ -s $LS_USER_STATE/gnome-extensions.undisabled ]]; then
    gsettings set org.gnome.shell disabled-extensions "$(python3 -c '
import ast,sys; cur=ast.literal_eval(sys.argv[1] if sys.argv[1] != "@as []" else "[]"); drop=set(open(sys.argv[2]).read().split())
print([x for x in cur if x not in drop])' "$dis" "$LS_USER_STATE/gnome-extensions.undisabled")"
  fi
  _files_apply
  _disable_apply
  step "applying extension settings"
  _settings apply
  (( new )) && info "new or updated extensions take effect after you log out and back in"
  return 0
}

module_remove() {
  [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] would restore extension settings and uninstall: $(cat "$LS_USER_STATE/gnome-extensions.installed" 2>/dev/null | tr '\n' ' ')"; return 0; }
  _dt remove --base /org/gnome/shell/extensions/ --prev "$LS_USER_STATE/gnome-extensions.prev.json"
  _dt remove --base / --prev "$LS_USER_STATE/gnome-extensions-enabled.prev.json"
  _disable_undo
  if [[ -s $LS_USER_STATE/gnome-extensions.undisabled ]]; then
    local cur; cur=$(gsettings get org.gnome.shell disabled-extensions)
    gsettings set org.gnome.shell disabled-extensions "$(python3 -c '
import ast,sys; cur=ast.literal_eval(sys.argv[1] if sys.argv[1] != "@as []" else "[]"); add=open(sys.argv[2]).read().split()
print(cur+[x for x in add if x not in cur])' "$cur" "$LS_USER_STATE/gnome-extensions.undisabled")"
    rm -f "$LS_USER_STATE/gnome-extensions.undisabled"
  fi
  local u
  if [[ -r $LS_USER_STATE/gnome-extensions.installed ]]; then
    while IFS= read -r u; do
      if [[ -n $u ]]; then gnome-extensions uninstall "$u" || true; rm -rf "${EXT_HOME:?}/$u"; [[ $u != decal@decal ]] || _strip_app_accent; fi
    done < "$LS_USER_STATE/gnome-extensions.installed"
    rm -f "$LS_USER_STATE/gnome-extensions.installed"
  fi
  rm -f "$ICON_DIR"/gnome-logo-*.svg "$ICON_DIR"/logo-*.svg
  local d; if [[ -r $FILES_REC ]]; then while IFS= read -r d; do if [[ -n $d ]]; then _file_restore "$d"; fi; done < <(cat "$FILES_REC"); rm -f "$FILES_REC"; fi
}

module_status() {
  local u missing=() pending=() s wait=""
  for u in $(_uuids); do
    if _loaded "$u"; then :; elif _on_disk "$u"; then pending+=("$u"); else missing+=("$u"); fi
  done
  if (( ${#P_file[@]} )); then s=$(_settings status | tail -1); else s=installed; fi
  if (( ${#pending[@]} )); then wait="${#pending[@]} active after you log out and back in"; fi
  if [[ $s == not-installed ]]; then echo "not-installed"
  elif (( ${#missing[@]} )) || [[ $s != installed ]]; then echo "partial (${#missing[@]} not installed${wait:+; $wait}; settings: $s)"
  else echo "installed${wait:+ ($wait)}"; fi
}
module_capture() { python3 "$LS_REPO/lib/dconf_tool.py" capture --base /org/gnome/shell/extensions/; }
# stamp: the extensions that are on (and the distro's you turned off), their settings changed from default, the
# config files those settings point to in ~/.config, and decal's panel logo
STAMP_LIVE=1
module_stamp() {
  have gnome-extensions || return 0
  local k rest en=() dis=() lp logo="" color="" n f rel files=()
  while read -r k rest; do
    case $k in enable) read -ra en <<<"$rest" ;; disable) read -ra dis <<<"$rest" ;; esac
  done < <(python3 "$LS_REPO/lib/stamp.py" extensions)
  (( ${#en[@]} )) || return 0
  lp=$(dconf read /org/gnome/shell/extensions/Logo-menu/custom-icon-path 2>/dev/null | tr -d "'")
  if [[ $lp == "$ICON_DIR"/* && -r $lp ]]; then   # the logo decal recoloured: colour in its name
    if [[ $(basename "$lp") =~ -([0-9a-fA-F]{6})\.svg$ ]]; then color="#${BASH_REMATCH[1]}"; fi
    if [[ $(basename "$lp") == logo-* ]]; then logo=$(stamp_copy "$lp" gnome/logo.svg); fi
  else lp=""; fi
  n=$(python3 "$LS_REPO/lib/stamp.py" dconf --out "$STAMP_DIR/gnome/extensions.ini" --extensions "${en[@]}" ${lp:+--replace "$lp=@LOGO_PATH@"})
  if (( n > 0 )); then
    local pat='@HOME@/[.]config/[^"'"'"' ]*'   # config files the settings point to
    while IFS= read -r f; do
      rel=${f#@HOME@/.config/}; [[ -f $HOME/.config/$rel ]] || continue
      files+=("\"$rel\" = \"$(stamp_copy "$HOME/.config/$rel" "gnome/files/$rel")\"")
    done < <(grep -oE "$pat" "$STAMP_DIR/gnome/extensions.ini" | sort -u)
  fi
  stamp_note "gnome-extensions: ${#en[@]} on${dis[*]:+, ${#dis[@]} distro ones off}, $n settings changed${logo:+, panel logo}"
  echo "[gnome-extensions]"
  echo "enable = $(toml_list "${en[@]}")"
  if (( ${#dis[@]} )); then echo "disable = $(toml_list "${dis[@]}")"; fi
  if (( n > 0 )); then echo 'file = "gnome/extensions.ini"'; fi
  if [[ -n $logo ]]; then echo "logo = \"$logo\""; fi
  if [[ -n $color ]]; then echo "logo-color = \"$color\""; fi
  if (( ${#files[@]} )); then echo "[gnome-extensions.files]"; printf '%s\n' "${files[@]}"; fi
}
