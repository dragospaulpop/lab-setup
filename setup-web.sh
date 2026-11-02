#!/usr/bin/env bash
# setup-web.sh - check (and, with --install, set up) the tools of the Advanced Web Development course.
# macOS and Linux (including WSL). bash 3.2 or newer.
#
#   ./setup-web.sh                      check only: prints a table, changes nothing
#   ./setup-web.sh --install            install or upgrade what is missing or too old, then check again
#   ./setup-web.sh --install --dry-run  print every command it would run, run none
#   ./setup-web.sh --only node,bun      limit the check (and the install) to these tools
#   ./setup-web.sh --install --force    redo the install even for tools that are fine (with --only, to repair one)
#
# Prefers Homebrew (no sudo). Without it, tools land in your home folder; only a few apt steps
# need sudo, and they ask you for the password in front of you. No telemetry. Every download comes
# from the tool's official site; where the site publishes a checksum, the script checks it.
# PATH is added to your shell startup file (~/.bashrc, or ~/.zprofile
# on macOS) and to this run. README.md says where each route comes from.

set -Eeuo pipefail
trap 'say ""; say "Stopped: a step above failed (line $LINENO). Fix what it says and run again; the script is safe to repeat."' ERR

INSTALL=0; DRY=0; FORCE=0; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=1 ;;
    --dry-run) DRY=1 ;;
    --force) FORCE=1 ;;
    --only) ONLY="${2:-}"; shift ;;
    --only=*) ONLY="${1#--only=}" ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)"; exit 2 ;;
  esac
  shift
done

# ---- settings you may want to read --------------------------------------------------------------
OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS-$ARCH" in Linux-x86_64|Linux-aarch64|Darwin-arm64|Darwin-x86_64) ;; *) echo "Unsupported system: $OS $ARCH"; exit 2 ;; esac
NODE_DIR="$HOME/.local/node"
RC="$HOME/.bashrc"; [ "$OS" = Darwin ] && RC="$HOME/.zprofile"

# ---- helpers ------------------------------------------------------------------------------------
say() { printf '%s\n' "$*"; }

# put Homebrew on this run's PATH when it is installed but not on PATH yet
for b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  if ! command -v brew >/dev/null 2>&1 && [ -x "$b" ]; then eval "$("$b" shellenv)"; fi
done
HAVE_BREW=0; command -v brew >/dev/null 2>&1 && HAVE_BREW=1

ver() { grep -Eo '[0-9]+(\.[0-9]+)+' | head -n 1 || true; }       # first "1.2.3" on stdin

older() {                                                        # older A B: A < B, numeric, dot-separated
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)" = "$1" ]
}

run() {                                                          # print (copy-pasteable), then run unless --dry-run
  printf '    >'; printf ' %q' "$@"; printf '\n'
  [ "$DRY" = 1 ] || "$@"
}

brew_get() {                                                     # install it, or upgrade it when it is already there
  if brew list "${@: -1}" >/dev/null 2>&1; then run brew upgrade "$@"; else run brew install "$@"; fi
}

persist() {                                                      # add a line to the shell startup file once + run it now
  say "    > add to $RC: $1"
  [ "$DRY" = 1 ] && return 0
  grep -qxF "$1" "$RC" 2>/dev/null || printf '%s\n' "$1" >> "$RC"
  eval "$1"
}

add_path() { persist "export PATH=\"$1:\$PATH\""; }

fetch() { run curl -fsSL --retry 3 -o "$2" "$1"; }

check_sha256() {                                                 # check_sha256 FILE EXPECTED
  if [ "$DRY" = 1 ]; then say "    > check the SHA-256 of $1 against $2"; return 0; fi
  local got
  if command -v sha256sum >/dev/null 2>&1; then got="$(sha256sum "$1" | cut -d' ' -f1)"; else got="$(shasum -a 256 "$1" | cut -d' ' -f1)"; fi
  [ "$got" = "$2" ] || { say "    checksum mismatch for $1 (got $got, wanted $2)"; return 1; }
  say "    SHA-256 matches."
}

apt_install() { run sudo apt-get install -y "$@"; }             # asks for your password, in front of you

unpack_to() {                                                    # unpack_to ARCHIVE DEST: the archive's one top folder becomes DEST
  say "    > unpack $1 as $2"
  [ "$DRY" = 1 ] && return 0
  local t; t="$(mktemp -d)"
  case "$1" in *.zip) unzip -q "$1" -d "$t" ;; *.tar.xz) tar -xJf "$1" -C "$t" ;; *) tar -xzf "$1" -C "$t" ;; esac
  rm -rf "$2"; mkdir -p "$(dirname "$2")"
  mv "$t"/* "$2"; rm -rf "$t"
}

workdir() { WORK="$(mktemp -d)"; }
trap 'rm -rf "${WORK:-}"' EXIT

# ---- the table of tools -------------------------------------------------------------------------
# id | name | needed (text) | min version. For each id: get_<id> prints the found version (or nothing),
# setup_<id> installs or upgrades it.
TOOLS='git|Git|2.30+|2.30
gh|GitHub CLI|2.40+|2.40
node|Node.js LTS|22+|22.0
bun|Bun|1.1+|1.1
code|VS Code|1.90+|1.90'

get_git()      { command -v git >/dev/null 2>&1 && git --version | ver; }
get_gh()       { command -v gh >/dev/null 2>&1 && gh --version | ver; }
get_node()     { command -v node >/dev/null 2>&1 && node --version | ver; }
get_bun()      { command -v bun >/dev/null 2>&1 && bun --version | ver; }
get_code()     { command -v code >/dev/null 2>&1 && code --version 2>/dev/null | head -n 1 | ver; }

setup_git() {
  if [ "$HAVE_BREW" = 1 ]; then brew_get git
  elif [ "$OS" = Darwin ]; then run xcode-select --install
  else apt_install git; fi
}
setup_gh() {
  if [ "$HAVE_BREW" = 1 ]; then brew_get gh
  elif [ "$OS" = Darwin ]; then say "    install Homebrew first (https://brew.sh), then run this again"; return 0
  else apt_install gh; fi          # the distro's package; if it is older than the table asks, see https://cli.github.com
}
setup_node() {
  if [ "$HAVE_BREW" = 1 ]; then brew_get node; return; fi
  # no Homebrew: the official tarball, checksum from nodejs.org's SHASUMS256.txt
  local v os; v="$(set +o pipefail; curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null | tr '{' '\n' | grep '"lts":"' | head -n 1 | grep -Eo '"version":"v[0-9.]+"' | cut -d'"' -f4)"   # newest LTS; head closes the pipe early
  [ -n "$v" ] || { say "    could not read the newest Node LTS from nodejs.org"; exit 1; }
  case "$OS-$ARCH" in Linux-x86_64) os=linux-x64;; Linux-aarch64) os=linux-arm64;; Darwin-arm64) os=darwin-arm64;; *) os=darwin-x64;; esac
  workdir
  fetch "https://nodejs.org/dist/$v/node-$v-$os.tar.xz" "$WORK/node.tar.xz"
  check_sha256 "$WORK/node.tar.xz" "$(curl -fsSL "https://nodejs.org/dist/$v/SHASUMS256.txt" | grep "node-$v-$os.tar.xz" | cut -d' ' -f1)"
  unpack_to "$WORK/node.tar.xz" "$NODE_DIR"
  add_path "$NODE_DIR/bin"
}
setup_bun() {
  if [ "$HAVE_BREW" = 1 ]; then brew_get oven-sh/bun/bun
  else
    say "    bun.sh's own install script (https://bun.com/install), needs 'unzip'"
    [ "$DRY" = 1 ] && { say "    > curl -fsSL https://bun.com/install | bash"; return 0; }
    curl -fsSL https://bun.com/install | bash
    add_path "$HOME/.bun/bin"
  fi
}
setup_code() {
  if [ "$OS" = Darwin ] && [ "$HAVE_BREW" = 1 ]; then brew_get --cask visual-studio-code
  else say "    not scripted here: install VS Code from https://code.visualstudio.com/docs/setup/linux (in WSL, use the Windows VS Code and its WSL extension)"; fi
}

# ---- check, table, install ----------------------------------------------------------------------
ids() { printf '%s\n' "$TOOLS" | cut -d'|' -f1; }
field() { printf '%s\n' "$TOOLS" | grep "^$1|" | cut -d'|' -f"$2"; }

SELECTED="$(ids)"
if [ -n "$ONLY" ]; then
  for w in $(echo "$ONLY" | tr ',' ' '); do
    ids | grep -qx "$w" || { say "Unknown tool: $w. Choose from: $(ids | tr '\n' ' ')"; exit 2; }
  done
  SELECTED="$(ids | grep -xFf <(echo "$ONLY" | tr ',' '\n'))"
fi

STATUS=""   # lines "id status"
check_one() {                       # sets FOUND and ST for tool $1
  local min; min="$(field "$1" 4)"
  FOUND="$("get_$1" 2>/dev/null || true)"
  if [ -z "$FOUND" ]; then FOUND="-"; ST=missing
  elif [ -n "$min" ] && older "$(printf '%s' "$FOUND" | ver)" "$min"; then ST="too old"
  else ST=ok; fi
}

show_table() {
  STATUS=""
  say ""
  printf '%-16s%-24s%-22s%s\n' Tool Needed Found Status
  printf '%-16s%-24s%-22s%s\n' ---- ------ ----- ------
  for id in $SELECTED; do
    check_one "$id"
    STATUS="$STATUS$id|$ST
"
    printf '%-16s%-24s%-22s%s\n' "$(field "$id" 2)" "$(field "$id" 3)" "$FOUND" "$ST"
  done
  say ""
}

say "setup-web.sh - ${HOSTNAME:-$(uname -n)}, user $(id -un), $OS $ARCH, bash $BASH_VERSION"
show_table
TODO="$(printf '%s' "$STATUS" | { if [ "$FORCE" = 1 ]; then cat; else grep -v '|ok$'; fi; } | cut -d'|' -f1 || true)"

if [ "$INSTALL" = 0 ]; then
  if [ -z "$TODO" ]; then say "Everything is in place. Nothing to do."
  else say "$(echo "$TODO" | wc -l | tr -d ' ') tool(s) need work. Nothing was changed. To install or upgrade them, run again with --install (add --dry-run to see the commands first)."; fi
  exit 0
fi
[ -n "$TODO" ] || { say "Everything is in place. Nothing to do."; exit 0; }

for id in $TODO; do
  say "== $(field "$id" 2): $(printf '%s' "$STATUS" | grep "^$id|" | cut -d'|' -f2)"
  "setup_$id"
done

say ""
if [ "$DRY" = 1 ]; then say "Dry run: nothing was changed."; show_table; exit 0; fi
say "Checking again:"
show_table
say "Open a NEW terminal (or run: source $RC) to be sure every tool is on its PATH."
