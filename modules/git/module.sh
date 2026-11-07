# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Git user identity, default branch, signing keys, and core workflow preferences"
MODULE_NEEDS_ROOT=0
STAMP_LIVE=1

PREV_REC="$LS_USER_STATE/git.prev"
IGNORE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"

_git_set() {
  local k=$1 v=$2 old
  if ! grep -q "^$k=" "$PREV_REC" 2>/dev/null; then
    if old=$(git config --global --get "$k" 2>/dev/null); then
      state_append "$PREV_REC" "$k=$old"
    else
      state_append "$PREV_REC" "$k=__UNSET__"
    fi
  fi
  if [[ $LS_DRY_RUN == 1 ]]; then
    log "[dry-run] git config --global $k $v"
  else
    git config --global "$k" "$v"
  fi
}

_apply_ignores() {
  (( ${#P_ignores[@]} )) || return 0
  mkdir -p "$(dirname "$IGNORE_FILE")"
  if [[ -f $IGNORE_FILE ]]; then
    sed -i '/^# decal git: begin/,/^# decal git: end/d' "$IGNORE_FILE"
  fi
  if [[ $LS_DRY_RUN == 1 ]]; then
    log "[dry-run] git ignores: ${P_ignores[*]}"
    return 0
  fi
  {
    echo "# decal git: begin"
    printf '%s\n' "${P_ignores[@]}"
    echo "# decal git: end"
  } >> "$IGNORE_FILE"
}

module_add() {
  have git || die "git is not installed"
  mkdir -p "$LS_USER_STATE"

  [[ -n $P_name ]] && _git_set user.name "$P_name"
  [[ -n $P_email ]] && _git_set user.email "$P_email"
  [[ -n $P_default_branch ]] && _git_set init.defaultBranch "$P_default_branch"
  [[ -n $P_editor ]] && _git_set core.editor "$P_editor"
  [[ -n $P_signing_key ]] && _git_set user.signingkey "$P_signing_key"
  [[ -n $P_sign_commits ]] && _git_set commit.gpgsign "$P_sign_commits"
  [[ -n $P_auto_setup_remote ]] && _git_set push.autoSetupRemote "$P_auto_setup_remote"
  [[ -n $P_pull_rebase ]] && _git_set pull.rebase "$P_pull_rebase"

  local al
  for al in "${!P_aliases[@]}"; do
    _git_set "alias.$al" "${P_aliases[$al]}"
  done

  _apply_ignores
  return 0
}

module_remove() {
  if [[ -r $PREV_REC ]]; then
    local line k v
    while IFS= read -r line; do
      [[ -n $line && $line == *"="* ]] || continue
      k="${line%%=*}"
      v="${line#*=}"
      if [[ $v == "__UNSET__" ]]; then
        git config --global --unset "$k" 2>/dev/null || true
      else
        git config --global "$k" "$v"
      fi
    done < "$PREV_REC"
    rm -f "$PREV_REC"
  fi
  if [[ -f $IGNORE_FILE ]]; then
    sed -i '/^# decal git: begin/,/^# decal git: end/d' "$IGNORE_FILE"
    if [[ ! -s $IGNORE_FILE ]]; then rm -f "$IGNORE_FILE"; fi
  fi
  return 0
}

module_status() {
  have git || { echo "not-installed (git not found)"; return 0; }
  local mismatches=() cur
  if [[ -n $P_name ]]; then
    cur=$(git config --global --get user.name 2>/dev/null || true)
    [[ $cur == "$P_name" ]] || mismatches+=("user.name")
  fi
  if [[ -n $P_email ]]; then
    cur=$(git config --global --get user.email 2>/dev/null || true)
    [[ $cur == "$P_email" ]] || mismatches+=("user.email")
  fi
  if [[ -n $P_default_branch ]]; then
    cur=$(git config --global --get init.defaultBranch 2>/dev/null || true)
    [[ $cur == "$P_default_branch" ]] || mismatches+=("init.defaultBranch")
  fi
  local al
  for al in "${!P_aliases[@]}"; do
    cur=$(git config --global --get "alias.$al" 2>/dev/null || true)
    [[ $cur == "${P_aliases[$al]}" ]] || mismatches+=("alias.$al")
  done

  if (( ${#mismatches[@]} )); then
    echo "partial (mismatch: ${mismatches[*]})"
  else
    echo "installed"
  fi
}

module_stamp() {
  have git || return 0
  local name email branch editor skey sign remote rebase
  name=$(git config --global user.name 2>/dev/null || true)
  email=$(git config --global user.email 2>/dev/null || true)
  branch=$(git config --global init.defaultBranch 2>/dev/null || true)
  editor=$(git config --global core.editor 2>/dev/null || true)
  skey=$(git config --global user.signingkey 2>/dev/null || true)
  sign=$(git config --global --bool commit.gpgsign 2>/dev/null || true)
  remote=$(git config --global --bool push.autoSetupRemote 2>/dev/null || true)
  rebase=$(git config --global --bool pull.rebase 2>/dev/null || true)

  [[ -n $name || -n $email || -n $branch || -n $editor || -n $skey ]] || return 0
  stamp_note "git: config (${name:-$email})"
  echo "[git]"
  [[ -n $name ]] && printf 'name = "%s"\n' "$name"
  [[ -n $email ]] && printf 'email = "%s"\n' "$email"
  [[ -n $branch ]] && printf 'default-branch = "%s"\n' "$branch"
  [[ -n $editor ]] && printf 'editor = "%s"\n' "$editor"
  [[ -n $skey ]] && printf 'signing-key = "%s"\n' "$skey"
  [[ -n $sign ]] && echo "sign-commits = $sign"
  [[ -n $remote ]] && echo "auto-setup-remote = $remote"
  [[ -n $rebase ]] && echo "pull-rebase = $rebase"
}
