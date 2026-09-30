#!/usr/bin/env bash
# Reasonix global launcher — source-install shell for the native binary.
# Intercepts custom maintenance flags, then execs the real CLI.
#
# Custom commands (handled by this wrapper, not the binary):
#   reasonix upgrade | update | -update | --update | self-update
#       git pull your tracking branch, rebuild, reinstall global binary
#   reasonix upgrade --check
#       fetch and report whether origin is ahead (no rebuild)
#   reasonix upgrade --force
#       rebuild and reinstall even when already on origin
#   reasonix -rebuild | --rebuild
#       rebuild from local source without pulling
#   reasonix -status | --status
#       show wrapper, binary, source repo, branch, and versions
#   reasonix -path | --path
#       print the source checkout path
#   reasonix -branch [NAME] | --branch [NAME]
#       show or set the tracking branch used by -update
#   reasonix -shell-help | --shell-help
#       document these wrapper commands
#
# Everything else is forwarded to the real binary, including:
#   reasonix              # interactive TUI
#   reasonix run "..."
#   reasonix setup
#
# This is a source install. Do not forward `upgrade`/`update` to the
# official GitHub release updater: that path rejects dev SHA builds.

set -euo pipefail

INSTALL_ENV="${REASONIX_INSTALL_ENV:-$HOME/.reasonix/install.env}"

# shellcheck disable=SC1090
if [[ -f "$INSTALL_ENV" ]]; then
  # shellcheck source=/dev/null
  source "$INSTALL_ENV"
fi

SOURCE_DIR="${REASONIX_SOURCE_DIR:-$HOME/Desktop/developer/DeepSeek-Reasonix}"
REMOTE="${REASONIX_REMOTE:-origin}"
BRANCH="${REASONIX_BRANCH:-main-v2}"
REAL_BIN="${REASONIX_REAL_BIN:-$HOME/.local/share/reasonix/bin/reasonix}"
WRAPPER_BIN="${REASONIX_WRAPPER_BIN:-$HOME/.local/bin/reasonix}"
GO_BIN="${REASONIX_GO_BIN:-}"

die() {
  printf 'reasonix-shell: %s\n' "$*" >&2
  exit 1
}

ensure_go() {
  if [[ -n "$GO_BIN" && -x "$GO_BIN" ]]; then
    export PATH="$(dirname "$GO_BIN"):$PATH"
    return
  fi
  if command -v go >/dev/null 2>&1; then
    return
  fi
  for candidate in /opt/homebrew/bin/go /usr/local/go/bin/go "$HOME/go/bin/go"; do
    if [[ -x "$candidate" ]]; then
      export PATH="$(dirname "$candidate"):$PATH"
      return
    fi
  done
  die "go not found on PATH. Install with: brew install go"
}

save_install_env() {
  mkdir -p "$(dirname "$INSTALL_ENV")"
  cat >"$INSTALL_ENV" <<EOF
# Reasonix source-install settings (used by ~/.local/bin/reasonix wrapper)
# Edit these when you move the clone or switch the tracking branch.

REASONIX_SOURCE_DIR="$SOURCE_DIR"
REASONIX_REMOTE="$REMOTE"
REASONIX_BRANCH="$BRANCH"
REASONIX_REAL_BIN="$REAL_BIN"
REASONIX_WRAPPER_BIN="$WRAPPER_BIN"
EOF
}

require_source() {
  [[ -d "$SOURCE_DIR/.git" ]] || die "source checkout missing: $SOURCE_DIR"
  [[ -f "$SOURCE_DIR/Makefile" ]] || die "not a Reasonix source tree: $SOURCE_DIR"
}

install_binary() {
  local built="$SOURCE_DIR/bin/reasonix"
  [[ -x "$built" ]] || die "build did not produce $built"
  mkdir -p "$(dirname "$REAL_BIN")"
  # Atomic replace so a running shell never sees a partial binary.
  local tmp="${REAL_BIN}.new.$$"
  cp "$built" "$tmp"
  chmod 755 "$tmp"
  mv -f "$tmp" "$REAL_BIN"
}

# User environment lives outside the git checkout. Snapshot it before a rebuild
# or pull and put secrets back if that step removes them. A config.toml the new
# binary migrates is left in place.
REASONIX_HOME_DIR="${REASONIX_HOME:-$HOME/.reasonix}"
PRESERVE_SNAP=""

snapshot_user_env() {
  PRESERVE_SNAP="$(mktemp -d "${TMPDIR:-/tmp}/reasonix-env.XXXXXX")"
  local f
  for f in .env install.env config.toml; do
    if [[ -f "$REASONIX_HOME_DIR/$f" ]]; then
      cp -p "$REASONIX_HOME_DIR/$f" "$PRESERVE_SNAP/$f"
    fi
  done
}

restore_user_env() {
  local snap="${PRESERVE_SNAP:-}"
  [[ -n "$snap" && -d "$snap" ]] || return 0
  mkdir -p "$REASONIX_HOME_DIR"
  if [[ -f "$snap/.env" ]]; then
    if [[ ! -s "$REASONIX_HOME_DIR/.env" ]] || ! grep -q '^DEEPSEEK_API_KEY=.' "$REASONIX_HOME_DIR/.env"; then
      cp -p "$snap/.env" "$REASONIX_HOME_DIR/.env"
      printf 'reasonix-shell: restored %s\n' "$REASONIX_HOME_DIR/.env" >&2
    fi
  fi
  if [[ -f "$snap/install.env" && ! -s "$REASONIX_HOME_DIR/install.env" ]]; then
    cp -p "$snap/install.env" "$REASONIX_HOME_DIR/install.env"
    printf 'reasonix-shell: restored %s\n' "$REASONIX_HOME_DIR/install.env" >&2
  fi
  if [[ -f "$snap/config.toml" && ! -s "$REASONIX_HOME_DIR/config.toml" ]]; then
    cp -p "$snap/config.toml" "$REASONIX_HOME_DIR/config.toml"
    printf 'reasonix-shell: restored %s\n' "$REASONIX_HOME_DIR/config.toml" >&2
  fi
  rm -rf "$snap"
  PRESERVE_SNAP=""
}

install_wrapper() {
  local src="$SOURCE_DIR/scripts/source-install-wrapper.sh"
  [[ -f "$src" ]] || return 0
  mkdir -p "$(dirname "$WRAPPER_BIN")"
  local tmp="${WRAPPER_BIN}.new.$$"
  cp "$src" "$tmp"
  chmod 755 "$tmp"
  mv -f "$tmp" "$WRAPPER_BIN"
}

cmd_shell_help() {
  cat <<'EOF'
Reasonix shell wrapper — source-tracking helpers

  reasonix upgrade              Pull tracking branch, rebuild, reinstall
  reasonix update               Same as upgrade
  reasonix upgrade --check      Fetch and report whether origin is ahead
  reasonix upgrade --force      Rebuild even if already on origin
  reasonix -update              Same as upgrade
  reasonix --update             Same as upgrade
  reasonix self-update          Same as upgrade
  reasonix -rebuild             Rebuild from local tree (no git pull)
  reasonix --rebuild            Same as -rebuild
  reasonix -status              Show install / git / version info
  reasonix --status             Same as -status
  reasonix -path                Print source checkout path
  reasonix --path               Same as -path
  reasonix -branch              Print tracking branch
  reasonix -branch NAME         Set tracking branch for future -update
  reasonix -shell-help          This help

Config file: ~/.reasonix/install.env
Real binary: ~/.local/share/reasonix/bin/reasonix
Wrapper:     ~/.local/bin/reasonix

This source install tracks origin/main-v2 in the local checkout
(override with ~/.reasonix/install.env). Upgrade keeps local commits
by rebasing them onto that branch, and it restores ~/.reasonix/.env
and install.env if a rebuild removes them. Official GitHub release
tarballs are not used — those reject this SHA-versioned binary.
EOF
}

cmd_status() {
  local real_ver="(missing)"
  local git_head="(n/a)"
  local git_branch="(n/a)"
  local dirty=""

  if [[ -x "$REAL_BIN" ]]; then
    real_ver="$("$REAL_BIN" --version 2>/dev/null || echo unknown)"
  fi
  if [[ -d "$SOURCE_DIR/.git" ]]; then
    git_head="$(git -C "$SOURCE_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    git_branch="$(git -C "$SOURCE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    if ! git -C "$SOURCE_DIR" diff --quiet 2>/dev/null || ! git -C "$SOURCE_DIR" diff --cached --quiet 2>/dev/null; then
      dirty=" (dirty working tree)"
    fi
  fi

  cat <<EOF
Reasonix source install
  wrapper:     $WRAPPER_BIN
  real binary: $REAL_BIN
  version:     $real_ver
  source:      $SOURCE_DIR
  remote:      $REMOTE
  track branch:$BRANCH
  git HEAD:    $git_head on $git_branch$dirty
  install env: $INSTALL_ENV
  which:       $(command -v reasonix 2>/dev/null || echo not-on-PATH)
EOF
}

cmd_path() {
  printf '%s\n' "$SOURCE_DIR"
}

cmd_branch() {
  if [[ $# -eq 0 || -z "${1:-}" ]]; then
    printf '%s\n' "$BRANCH"
    return
  fi
  BRANCH="$1"
  save_install_env
  printf 'Tracking branch set to: %s\n' "$BRANCH"
}

cmd_rebuild() {
  require_source
  ensure_go
  snapshot_user_env
  trap restore_user_env RETURN
  printf 'reasonix-shell: building from %s ...\n' "$SOURCE_DIR" >&2
  (
    cd "$SOURCE_DIR"
    make build
  )
  install_binary
  install_wrapper
  restore_user_env
  trap - RETURN
  printf 'reasonix-shell: installed %s\n' "$REAL_BIN" >&2
  "$REAL_BIN" version --verbose 2>/dev/null || "$REAL_BIN" --version
}

short_sha() {
  local rev="$1"
  git -C "$SOURCE_DIR" rev-parse --short=9 "$rev" 2>/dev/null || printf '%s' "$rev"
}

ensure_tracking_branch() {
  local current
  current="$(git -C "$SOURCE_DIR" rev-parse --abbrev-ref HEAD)"
  if [[ "$current" == "$BRANCH" ]]; then
    return
  fi
  if git -C "$SOURCE_DIR" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$SOURCE_DIR" checkout "$BRANCH"
  elif git -C "$SOURCE_DIR" show-ref --verify --quiet "refs/remotes/$REMOTE/$BRANCH"; then
    git -C "$SOURCE_DIR" checkout -B "$BRANCH" "$REMOTE/$BRANCH"
  else
    die "branch not found: $BRANCH (remote $REMOTE)"
  fi
}

cmd_update() {
  local force=0
  local check_only=0
  local arg
  for arg in "$@"; do
    case "$arg" in
      -h|--help)
        cmd_shell_help
        return 0
        ;;
      --check)
        check_only=1
        ;;
      --force)
        force=1
        ;;
      --channel|--channel=*)
        printf 'reasonix-shell: ignoring %s (source install tracks %s/%s)\n' "$arg" "$REMOTE" "$BRANCH" >&2
        ;;
      stable|preview|canary|beta|next)
        printf 'reasonix-shell: ignoring release channel %s (source install tracks %s/%s)\n' "$arg" "$REMOTE" "$BRANCH" >&2
        ;;
      *)
        die "unknown upgrade option: $arg (try: reasonix upgrade [--check] [--force])"
        ;;
    esac
  done

  require_source
  snapshot_user_env
  trap restore_user_env RETURN
  printf 'reasonix-shell: fetching %s/%s ...\n' "$REMOTE" "$BRANCH" >&2
  git -C "$SOURCE_DIR" fetch --prune "$REMOTE"
  ensure_tracking_branch

  local local_sha remote_sha
  local_sha="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
  remote_sha="$(git -C "$SOURCE_DIR" rev-parse "$REMOTE/$BRANCH")"
  local local_short remote_short
  local_short="$(short_sha HEAD)"
  remote_short="$(short_sha "$REMOTE/$BRANCH")"

  if [[ "$check_only" -eq 1 ]]; then
    if [[ "$local_sha" == "$remote_sha" ]]; then
      printf 'reasonix %s  already on %s/%s\n' "$local_short" "$REMOTE" "$BRANCH"
    else
      printf 'reasonix %s  update available → %s (%s/%s)\n' "$local_short" "$remote_short" "$REMOTE" "$BRANCH"
    fi
    return 0
  fi

  if [[ "$local_sha" == "$remote_sha" && "$force" -eq 0 ]]; then
    printf 'reasonix-shell: already on %s/%s (%s); use --force to rebuild\n' "$REMOTE" "$BRANCH" "$local_short" >&2
    "$REAL_BIN" version --verbose 2>/dev/null || "$REAL_BIN" --version
    return 0
  fi

  ensure_go
  printf 'reasonix-shell: updating %s from %s/%s ...\n' "$SOURCE_DIR" "$REMOTE" "$BRANCH" >&2
  (
    set -euo pipefail
    cd "$SOURCE_DIR"
    # Fast-forward when this checkout has no local commits. When it does,
    # replay those commits on top of the tracking branch so a private model
    # patch survives upgrade. Leave ~/.reasonix untouched; the caller restores
    # .env and install.env if a step removes them.
    if git merge-base --is-ancestor HEAD "$REMOTE/$BRANCH"; then
      git merge --ff-only "$REMOTE/$BRANCH"
    elif git merge-base --is-ancestor "$REMOTE/$BRANCH" HEAD; then
      printf 'reasonix-shell: keeping local commits on %s\n' "$BRANCH" >&2
    elif ! git rebase "$REMOTE/$BRANCH"; then
      git rebase --abort || true
      printf 'reasonix-shell: rebase onto %s/%s failed. Resolve it in %s\n' "$REMOTE" "$BRANCH" "$SOURCE_DIR" >&2
      exit 1
    fi
    make build
  )
  install_binary
  install_wrapper
  restore_user_env
  trap - RETURN
  printf 'reasonix-shell: update complete → %s\n' "$REAL_BIN" >&2
  "$REAL_BIN" version --verbose 2>/dev/null || "$REAL_BIN" --version
}

# --- dispatch custom shell commands before the real binary ---
case "${1:-}" in
  -update|--update|self-update|upgrade|update)
    shift || true
    cmd_update "$@"
    exit 0
    ;;
  -rebuild|--rebuild)
    shift || true
    cmd_rebuild "$@"
    exit 0
    ;;
  -status|--status)
    shift || true
    cmd_status "$@"
    exit 0
    ;;
  -path|--path)
    shift || true
    cmd_path "$@"
    exit 0
    ;;
  -branch|--branch)
    shift || true
    cmd_branch "$@"
    exit 0
    ;;
  -shell-help|--shell-help)
    cmd_shell_help
    exit 0
    ;;
esac

if [[ ! -x "$REAL_BIN" ]]; then
  die "real binary missing at $REAL_BIN — run: reasonix -rebuild"
fi

exec "$REAL_BIN" "$@"
