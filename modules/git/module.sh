# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Git user identity, default branch, signing keys, and core workflow preferences"
MODULE_NEEDS_ROOT=0
STAMP_LIVE=1

PREV_REC="$LS_USER_STATE/git.prev"
IGNORE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"

_git_prev_has() {
  [[ -r $PREV_REC ]] && awk -F= -v k="$1" '$1 == k { found=1; exit } END { exit !found }' "$PREV_REC"
}

_git_set() {
  local k=$1 v=$2 old
  [[ $k != *[=$'\n']* ]] || die "invalid git config key: $k"
  [[ $v != *$'\n'* ]] || die "git config value for $k cannot contain newlines"
  if ! _git_prev_has "$k"; then
    if old=$(git config --global --get "$k" 2>/dev/null); then :; else old="__UNSET__"; fi
    if [[ $LS_DRY_RUN != 1 ]]; then
      mkdir -p "$LS_USER_STATE"
      printf '%s=%s\n' "$k" "$old" >> "$PREV_REC"
    fi
  fi
  if [[ $LS_DRY_RUN == 1 ]]; then
    log "[dry-run] git config --global $k $v"
  else
    git config --global "$k" "$v"
  fi
}

_git_field_pairs() {
  printf '%s\n' \
    "user.name:${P_name}" \
    "user.email:${P_email}" \
    "init.defaultBranch:${P_default_branch}" \
    "core.editor:${P_editor}" \
    "user.signingkey:${P_signing_key}" \
    "commit.gpgsign:${P_sign_commits}" \
    "push.autoSetupRemote:${P_auto_setup_remote}" \
    "pull.rebase:${P_pull_rebase}"
}

_apply_ignores() {
  (( ${#P_ignores[@]} )) || return 0
  local pat
  for pat in "${P_ignores[@]}"; do
    [[ $pat != *$'\n'* ]] || die "git ignores cannot contain newlines"
  done
  printf '%s\n' "${P_ignores[@]}" | user_block_set "$IGNORE_FILE" "git"
}

module_add() {
  have git || die "git is not installed"

  local pair k v
  while IFS= read -r pair; do
    k=${pair%%:*}; v=${pair#*:}
    [[ -n $v ]] && _git_set "$k" "$v"
  done < <(_git_field_pairs)

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
        if [[ $LS_DRY_RUN == 1 ]]; then
          log "[dry-run] git config --global --unset $k"
        else
          git config --global --unset "$k" 2>/dev/null || true
        fi
      else
        run git config --global "$k" "$v"
      fi
    done < "$PREV_REC"
    run rm -f "$PREV_REC"
  fi
  user_block_set "$IGNORE_FILE" "git" </dev/null
  return 0
}

module_status() {
  have git || { echo "not-installed (git not found)"; return 0; }
  local mismatches=() total=0 have_n=0 pair k v cur
  while IFS= read -r pair; do
    k=${pair%%:*}; v=${pair#*:}
    [[ -n $v ]] || continue
    total=$((total + 1))
    case $k in
      commit.gpgsign|push.autoSetupRemote|pull.rebase)
        cur=$(git config --global --bool --get "$k" 2>/dev/null || true) ;;
      *)
        cur=$(git config --global --get "$k" 2>/dev/null || true) ;;
    esac
    if [[ $cur == "$v" ]]; then have_n=$((have_n + 1)); else mismatches+=("$k"); fi
  done < <(_git_field_pairs)

  local al
  for al in "${!P_aliases[@]}"; do
    total=$((total + 1))
    cur=$(git config --global --get "alias.$al" 2>/dev/null || true)
    if [[ $cur == "${P_aliases[$al]}" ]]; then have_n=$((have_n + 1)); else mismatches+=("alias.$al"); fi
  done

  if (( ${#P_ignores[@]} )); then
    total=$((total + 1))
    local cur_ig exp_ig
    cur_ig=$(user_block_get "$IGNORE_FILE" "git" 2>/dev/null || true)
    exp_ig=$(printf '%s\n' "${P_ignores[@]}")
    if [[ -n $cur_ig && $cur_ig == "$exp_ig" ]]; then have_n=$((have_n + 1)); else mismatches+=("ignores"); fi
  fi

  if (( total == 0 || have_n == total )); then
    echo "installed"
  elif (( have_n == 0 )); then
    echo "not-installed"
  else
    echo "partial (mismatch: ${mismatches[*]})"
  fi
}

module_stamp() {
  have git || return 0
  local name email branch editor skey sign remote rebase
  name=$(git config --global --get user.name 2>/dev/null || true)
  email=$(git config --global --get user.email 2>/dev/null || true)
  branch=$(git config --global --get init.defaultBranch 2>/dev/null || true)
  editor=$(git config --global --get core.editor 2>/dev/null || true)
  skey=$(git config --global --get user.signingkey 2>/dev/null || true)
  sign=$(git config --global --bool --get commit.gpgsign 2>/dev/null || true)
  remote=$(git config --global --bool --get push.autoSetupRemote 2>/dev/null || true)
  rebase=$(git config --global --bool --get pull.rebase 2>/dev/null || true)

  local aliases=() line ak av
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    ak=${line%% *}; ak=${ak#alias.}
    av=${line#* }
    [[ $ak == "$line" ]] && av=""
    if [[ $ak =~ ^[A-Za-z0-9_-]+$ ]]; then
      aliases+=("$ak = $(toml_str "$av")")
    else
      aliases+=("$(toml_str "$ak") = $(toml_str "$av")")
    fi
  done < <(git config --global --get-regexp '^alias\.' 2>/dev/null || true)

  local ignores=() pat
  if [[ -r $IGNORE_FILE ]]; then
    while IFS= read -r pat; do
      [[ -n $pat && $pat != "#"* ]] || continue
      ignores+=("$pat")
    done < "$IGNORE_FILE"
  fi

  [[ -n $name || -n $email || -n $branch || -n $editor || -n $skey || -n $sign || -n $remote || -n $rebase || ${#aliases[@]} -gt 0 || ${#ignores[@]} -gt 0 ]] || return 0
  stamp_note "git: config (${name:-${email:-${#aliases[@]} aliases}})"
  echo "[git]"
  [[ -n $name ]] && printf 'name = %s\n' "$(toml_str "$name")"
  [[ -n $email ]] && printf 'email = %s\n' "$(toml_str "$email")"
  [[ -n $branch ]] && printf 'default-branch = %s\n' "$(toml_str "$branch")"
  [[ -n $editor ]] && printf 'editor = %s\n' "$(toml_str "$editor")"
  [[ -n $skey ]] && printf 'signing-key = %s\n' "$(toml_str "$skey")"
  [[ -n $sign ]] && echo "sign-commits = $sign"
  [[ -n $remote ]] && echo "auto-setup-remote = $remote"
  [[ -n $rebase ]] && echo "pull-rebase = $rebase"
  (( ${#ignores[@]} )) && printf 'ignores = %s\n' "$(toml_list "${ignores[@]}")"
  if (( ${#aliases[@]} )); then
    echo ""
    echo "[git.aliases]"
    printf '%s\n' "${aliases[@]}"
  fi
}
