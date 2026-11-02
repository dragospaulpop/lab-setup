#!/usr/bin/env bash
# setup-mobile.sh - check (and, with --install, set up) the tools of the Mobile Apps course.
# macOS and Linux (including WSL). bash 3.2 or newer.
#
#   ./setup-mobile.sh                      check only: prints a table, changes nothing
#   ./setup-mobile.sh --install            install or upgrade what is missing or too old, then check again
#   ./setup-mobile.sh --install --dry-run  print every command it would run, run none
#   ./setup-mobile.sh --only flutter,jdk   limit the check (and the install) to these tools
#   ./setup-mobile.sh --install --force    redo the install even for tools that are fine (with --only, to repair one)
#
# Prefers Homebrew (no sudo). Without it, tools land in your home folder; only a few apt steps
# need sudo, and they ask you for the password in front of you. No telemetry. Every download comes
# from the tool's official site; where the site publishes a checksum, the script checks it.
# PATH, JAVA_HOME and ANDROID_HOME are added to your shell startup file (~/.bashrc, or ~/.zprofile
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
ANDROID_API=36                                   # Flutter's docs ask for API level 36
SDK_ROOT="${ANDROID_HOME:-$HOME/Android/Sdk}"
case "$SDK_ROOT" in /mnt/*) SDK_ROOT="$HOME/Android/Sdk" ;; esac   # WSL: never use the Windows PC's SDK
CMDLINE_BUILD=15859902                           # from developer.android.com/studio, "Command line tools only"
OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS-$ARCH" in
  Linux-x86_64)  CMDLINE_OS=linux; CMDLINE_SHA=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583; JDK_OS=linux-x64; ABI=x86_64 ;;
  Linux-aarch64) CMDLINE_OS=linux; CMDLINE_SHA=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583; JDK_OS=linux-aarch64; ABI=arm64-v8a ;;
  Darwin-arm64)  CMDLINE_OS=mac_arm64; CMDLINE_SHA=835b62a26162b229b441d1f6d4680383815a270809eb33522c0d480fa5002c4e; JDK_OS=macOS-aarch64; ABI=arm64-v8a ;;
  Darwin-x86_64) CMDLINE_OS=mac_x86_64; CMDLINE_SHA=c5a6378ab5cf7e0d5701921405115befff13e9ff7417fb588389338f8bd050f3; JDK_OS=macOS-x64; ABI=x86_64 ;;
  *) echo "Unsupported system: $OS $ARCH"; exit 2 ;;
esac
SYS_IMAGE="system-images;android-$ANDROID_API;google_apis;$ABI"
AVD_NAME="Pixel_7_API_$ANDROID_API"
FLUTTER_DIR="$HOME/develop/flutter"
NODE_DIR="$HOME/.local/node"
JDK_DIR="$HOME/.local/jdk-21"
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
sdk_tool() { echo "$SDK_ROOT/cmdline-tools/latest/bin/$1"; }

accept_licences() {
  say "    > accept the Android SDK licences (you accepted them by running --install; read them: https://developer.android.com/studio/terms)"
  [ "$DRY" = 1 ] || "$(sdk_tool sdkmanager)" --licenses --sdk_root="$SDK_ROOT" < <(yes) >/dev/null || true
}

find_java() {
  if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then echo "$JAVA_HOME/bin/java"
  elif command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then command -v java
  fi
}

# ---- the table of tools -------------------------------------------------------------------------
# id | name | needed (text) | min version. For each id: get_<id> prints the found version (or nothing),
# setup_<id> installs or upgrades it.
TOOLS='git|Git|2.30+|2.30
gh|GitHub CLI|2.40+|2.40
node|Node.js LTS|22+|22.0
bun|Bun|1.1+|1.1
code|VS Code|1.90+|1.90
jdk|JDK|17+|17.0
android|Android SDK|API '"$ANDROID_API"' + tools|
image|Emulator image|'"$AVD_NAME"'|
flutter|Flutter|3.47+ (stable)|3.47
supabase|Supabase CLI|2.0+|2.0
firebase|Firebase CLI|15+|15.0'

get_git()      { command -v git >/dev/null 2>&1 && git --version | ver; }
get_gh()       { command -v gh >/dev/null 2>&1 && gh --version | ver; }
get_node()     { command -v node >/dev/null 2>&1 && node --version | ver; }
get_bun()      { command -v bun >/dev/null 2>&1 && bun --version | ver; }
get_code()     { command -v code >/dev/null 2>&1 && code --version 2>/dev/null | head -n 1 | ver; }
get_jdk()      { local j; j="$(find_java)"; [ -n "$j" ] && "$j" -version 2>&1 | head -n 1 | ver; }
get_flutter()  { command -v flutter >/dev/null 2>&1 && flutter --version 2>/dev/null | head -n 1 | ver; }
get_supabase() { command -v supabase >/dev/null 2>&1 && supabase --version | ver; }
get_firebase() { command -v firebase >/dev/null 2>&1 && firebase --version 2>/dev/null | ver; }
get_android()  {
  [ -x "$(sdk_tool sdkmanager)" ] && [ -x "$SDK_ROOT/platform-tools/adb" ] && [ -d "$SDK_ROOT/platforms/android-$ANDROID_API" ] \
    && [ -d "$SDK_ROOT/build-tools/$ANDROID_API.0.0" ] && echo "API $ANDROID_API" || true
}
get_image()    {
  [ -d "$SDK_ROOT/system-images/android-$ANDROID_API/google_apis/$ABI" ] && [ -f "$HOME/.android/avd/$AVD_NAME.ini" ] \
    && echo "API $ANDROID_API, AVD ok" || true
}

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
setup_jdk() {
  if [ "$HAVE_BREW" = 1 ]; then
    brew_get openjdk@21
    local home; home="$(brew --prefix openjdk@21)/libexec"; [ "$OS" = Darwin ] && home="$home/openjdk.jdk/Contents/Home"
    persist "export JAVA_HOME=\"$home\""; add_path "$home/bin"
  else
    local url="https://aka.ms/download-jdk/microsoft-jdk-21-$JDK_OS.tar.gz"; workdir
    fetch "$url" "$WORK/jdk.tar.gz"
    check_sha256 "$WORK/jdk.tar.gz" "$(curl -fsSL "$url.sha256sum.txt" | cut -d' ' -f1)"
    unpack_to "$WORK/jdk.tar.gz" "$JDK_DIR"
    local home="$JDK_DIR"; [ "$OS" = Darwin ] && home="$JDK_DIR/Contents/Home"
    persist "export JAVA_HOME=\"$home\""; add_path "$home/bin"
  fi
}
setup_android() {
  if [ ! -x "$(sdk_tool sdkmanager)" ]; then
    workdir
    fetch "https://dl.google.com/android/repository/commandlinetools-${CMDLINE_OS}-${CMDLINE_BUILD}_latest.zip" "$WORK/cmdline.zip"
    check_sha256 "$WORK/cmdline.zip" "$CMDLINE_SHA"
    say "    > unpack into $SDK_ROOT/cmdline-tools/latest"
    if [ "$DRY" = 0 ]; then
      unzip -q "$WORK/cmdline.zip" -d "$WORK/out"
      mkdir -p "$SDK_ROOT/cmdline-tools"; rm -rf "$SDK_ROOT/cmdline-tools/latest"
      mv "$WORK/out/cmdline-tools" "$SDK_ROOT/cmdline-tools/latest"; rm -rf "$WORK"
    fi
  fi
  accept_licences
  run "$(sdk_tool sdkmanager)" --sdk_root="$SDK_ROOT" --install platform-tools emulator "platforms;android-$ANDROID_API" "build-tools;$ANDROID_API.0.0"
  persist "export ANDROID_HOME=\"$SDK_ROOT\""
  add_path "$SDK_ROOT/platform-tools"; add_path "$SDK_ROOT/emulator"; add_path "$SDK_ROOT/cmdline-tools/latest/bin"
}
setup_image() {
  accept_licences
  run "$(sdk_tool sdkmanager)" --sdk_root="$SDK_ROOT" --install "$SYS_IMAGE"
  say "    > avdmanager create avd --name $AVD_NAME --package '$SYS_IMAGE' --device pixel_7 --force"
  [ "$DRY" = 1 ] || echo no | "$(sdk_tool avdmanager)" create avd --name "$AVD_NAME" --package "$SYS_IMAGE" --device pixel_7 --force
}
setup_flutter() {
  if [ -x "$FLUTTER_DIR/bin/flutter" ]; then run "$FLUTTER_DIR/bin/flutter" upgrade
  else
    command -v python3 >/dev/null 2>&1 || { say "    python3 is needed to read Flutter's release list"; exit 1; }
    local os=linux; [ "$OS" = Darwin ] && os=macos
    local line; workdir
    # the stable release for this CPU, and its SHA-256, from Flutter's own release list
    line="$(curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/releases_$os.json" | python3 -c '
import json, sys, platform
d = json.load(sys.stdin)
arch = "arm64" if platform.machine() in ("arm64", "aarch64") else "x64"
for r in d["releases"]:
    if r["hash"] == d["current_release"]["stable"] and r.get("dart_sdk_arch", "x64") == arch:
        print(r["archive"], r["sha256"]); break')"
    local archive="${line% *}" sha="${line#* }"
    fetch "https://storage.googleapis.com/flutter_infra_release/releases/$archive" "$WORK/flutter.pkg"
    check_sha256 "$WORK/flutter.pkg" "$sha"
    unpack_to "$WORK/flutter.pkg" "$FLUTTER_DIR"
  fi
  add_path "$FLUTTER_DIR/bin"
  run flutter config --android-sdk "$SDK_ROOT"
}
setup_supabase() {
  if [ "$HAVE_BREW" = 1 ]; then brew_get supabase/tap/supabase
  elif [ "$OS" = Linux ]; then
    # supabase.com/docs: the .deb from GitHub Releases (dpkg needs sudo)
    workdir
    fetch "https://github.com/supabase/cli/releases/latest/download/supabase_linux_$(dpkg --print-architecture).deb" "$WORK/supabase.deb"
    run sudo dpkg -i "$WORK/supabase.deb"
  else say "    install Homebrew first (https://brew.sh), then run this again"; return 0; fi
}
setup_firebase() {
  # firebase.google.com/docs/cli: npm install -g firebase-tools; a prefix we cannot write to goes to ~/.local
  command -v npm >/dev/null 2>&1 || { say "    needs Node.js (npm) first"; exit 1; }
  if [ ! -w "$(npm prefix -g)" ]; then run npm config set prefix "$HOME/.local"; add_path "$HOME/.local/bin"; fi
  run npm install -g firebase-tools
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

say "setup-mobile.sh - ${HOSTNAME:-$(uname -n)}, user $(id -un), $OS $ARCH, bash $BASH_VERSION"
show_table
TODO="$(printf '%s' "$STATUS" | { if [ "$FORCE" = 1 ]; then cat; else grep -v '|ok$'; fi; } | cut -d'|' -f1 || true)"

if [ "$INSTALL" = 0 ]; then
  if [ -z "$TODO" ]; then say "Everything is in place. Nothing to do."
  else say "$(echo "$TODO" | wc -l | tr -d ' ') tool(s) need work. Nothing was changed. To install or upgrade them, run again with --install (add --dry-run to see the commands first)."; fi
  exit 0
fi
[ -n "$TODO" ] || { say "Everything is in place. Nothing to do."; exit 0; }

if echo "$TODO" | grep -qxE 'android|image'; then
  say "!! SLOW DOWNLOAD AHEAD: the Android SDK and the emulator image are about 2.6 GB together"
  say "!! (command-line tools 160 MB, emulator ~350 MB, platform + build-tools ~130 MB, system image ~1.9 GB)."
  say "!! Expect 10 to 30 minutes on a slow network. Keep this terminal open."
  say ""
fi

for id in $TODO; do
  say "== $(field "$id" 2): $(printf '%s' "$STATUS" | grep "^$id|" | cut -d'|' -f2)"
  "setup_$id"
done

say ""
if [ "$DRY" = 1 ]; then say "Dry run: nothing was changed."; show_table; exit 0; fi
say "Checking again:"
show_table
say "Open a NEW terminal (or run: source $RC) to be sure every tool is on its PATH."
