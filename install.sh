#!/bin/sh
# Install, upgrade or uninstall ai-cli-adapter.
#
#   curl -fsSL https://raw.githubusercontent.com/jinuthankachan/ai-cli-adapter-binaries/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/jinuthankachan/ai-cli-adapter-binaries/main/install.sh | sh -s -- --service
#   curl -fsSL https://raw.githubusercontent.com/jinuthankachan/ai-cli-adapter-binaries/main/install.sh | sh -s -- --uninstall
#
# Run with --help for all options.
set -eu

REPO="jinuthankachan/ai-cli-adapter-binaries"
BIN="ai-cli-adapter"
RELEASES_URL="https://github.com/$REPO/releases"
SYSTEMD_UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$BIN.service"
LAUNCHD_LABEL="io.github.jinuthankachan.ai-cli-adapter"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
DATA_DIR="${AI_CLI_ADAPTER_HOME:-$HOME/.ai-cli-adapter}"

usage() {
  cat <<EOF
Install, upgrade or uninstall $BIN (Linux and macOS).

Usage: install.sh [options]

  --version TAG   install this release, e.g. v0.2.0 (default: latest)
  --dir DIR       install directory (default: ~/.local/bin)
  --service       also run it in the background at login
                  (systemd user service on Linux, launchd agent on macOS)
  --uninstall     remove the binary and the background service
  --purge         with --uninstall: also delete $DATA_DIR
                  (config, API key, request log, working directories)
  -h, --help      show this help

Environment: VERSION and INSTALL_DIR work like --version and --dir.
EOF
}

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but was not found"; }

detect_target() {
  os=$(uname -s)
  arch=$(uname -m)
  case "$arch" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) die "unsupported CPU architecture: $arch (supported: x86_64, aarch64/arm64)" ;;
  esac
  case "$os" in
    Linux) TARGET="$arch-unknown-linux-musl" ;;
    Darwin)
      # An x86_64 shell under Rosetta still gets the native Apple Silicon build.
      if [ "$arch" = x86_64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" = 1 ]; then
        arch=aarch64
      fi
      TARGET="$arch-apple-darwin"
      ;;
    *) die "unsupported OS: $os (supported: Linux, macOS)" ;;
  esac
}

resolve_version() {
  if [ "$VERSION" != latest ]; then
    case "$VERSION" in v*) ;; *) VERSION="v$VERSION" ;; esac
    return
  fi
  # /releases/latest redirects to /releases/tag/<tag>, or to /releases when nothing is published.
  url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "$RELEASES_URL/latest") ||
    die "could not reach $RELEASES_URL"
  case "$url" in
    */releases/tag/*) VERSION=${url##*/} ;;
    *) die "no release has been published yet at $RELEASES_URL" ;;
  esac
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

install_binary() {
  need curl
  need tar
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 ||
    die "need sha256sum or shasum to verify the download"
  detect_target
  resolve_version

  asset="$BIN-$VERSION-$TARGET.tar.gz"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  say "Downloading $BIN $VERSION for $TARGET"
  curl -fSL --progress-bar -o "$tmp/$asset" "$RELEASES_URL/download/$VERSION/$asset" ||
    die "download failed: $RELEASES_URL/download/$VERSION/$asset"
  curl -fsSL -o "$tmp/SHA256SUMS" "$RELEASES_URL/download/$VERSION/SHA256SUMS" ||
    die "could not download SHA256SUMS for $VERSION"

  expected=$(awk -v f="$asset" '$2 == f || $2 == "*" f { print $1 }' "$tmp/SHA256SUMS")
  [ -n "$expected" ] || die "$asset is not listed in SHA256SUMS"
  [ "$(sha256 "$tmp/$asset")" = "$expected" ] || die "checksum mismatch for $asset; not installing"

  tar -xzf "$tmp/$asset" -C "$tmp"
  "$tmp/$BIN" --help >/dev/null 2>&1 || die "the downloaded binary does not run on this machine"

  mkdir -p "$INSTALL_DIR" 2>/dev/null || die "cannot create $INSTALL_DIR (choose another with --dir)"
  [ -w "$INSTALL_DIR" ] || die "$INSTALL_DIR is not writable (choose another with --dir, or run with sudo)"
  # Copy then rename, so a running instance keeps its old binary until restarted.
  cp "$tmp/$BIN" "$INSTALL_DIR/.$BIN.new"
  chmod 755 "$INSTALL_DIR/.$BIN.new"
  mv -f "$INSTALL_DIR/.$BIN.new" "$INSTALL_DIR/$BIN"
  say "Installed $INSTALL_DIR/$BIN"

  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *) warn "$INSTALL_DIR is not on your PATH. Add this line to your shell profile:
  export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
  esac
}

report_clis() {
  found=""
  for cli in claude codex agy; do
    if command -v "$cli" >/dev/null 2>&1; then found="$found $cli"; fi
  done
  if [ -n "$found" ]; then
    say "Backend CLIs found on PATH:$found"
  else
    warn "none of the backend CLIs (claude, codex, agy) is on your PATH; install and log in to at least one"
  fi
}

xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

install_service() {
  case "$(uname -s)" in
    Linux)
      command -v systemctl >/dev/null 2>&1 || die "--service needs systemd (systemctl not found)"
      mkdir -p "$(dirname "$SYSTEMD_UNIT")"
      cat >"$SYSTEMD_UNIT" <<EOF
[Unit]
Description=AI CLI Adapter (Anthropic/OpenAI/Gemini API over the claude, codex and agy CLIs)
After=network.target

[Service]
Type=simple
WorkingDirectory=%h
ExecStart=$INSTALL_DIR/$BIN
Restart=on-failure
RestartSec=3
# User services get a minimal PATH; keep the installer's PATH so the CLIs are found.
Environment="PATH=$PATH"

[Install]
WantedBy=default.target
EOF
      systemctl --user daemon-reload
      systemctl --user enable --quiet "$BIN"
      systemctl --user restart "$BIN"
      say "Service running: systemctl --user status $BIN"
      say "Logs:            journalctl --user -u $BIN -f"
      say "To keep it running while you are logged out: loginctl enable-linger $(id -un)"
      ;;
    Darwin)
      mkdir -p "$(dirname "$LAUNCHD_PLIST")" "$HOME/Library/Logs"
      cat >"$LAUNCHD_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LAUNCHD_LABEL</string>
  <key>ProgramArguments</key><array><string>$(xml_escape "$INSTALL_DIR/$BIN")</string></array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$(xml_escape "$PATH")</string></dict>
  <key>WorkingDirectory</key><string>$(xml_escape "$HOME")</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardOutPath</key><string>$(xml_escape "$HOME/Library/Logs/$BIN.log")</string>
  <key>StandardErrorPath</key><string>$(xml_escape "$HOME/Library/Logs/$BIN.log")</string>
</dict>
</plist>
EOF
      uid=$(id -u)
      launchctl bootout "gui/$uid/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
      # bootout finishes asynchronously; retry once if the old instance is still going away.
      launchctl bootstrap "gui/$uid" "$LAUNCHD_PLIST" 2>/dev/null ||
        { sleep 2; launchctl bootstrap "gui/$uid" "$LAUNCHD_PLIST"; }
      say "Service running: launchctl print gui/$uid/$LAUNCHD_LABEL"
      say "Logs:            tail -f ~/Library/Logs/$BIN.log"
      ;;
  esac
}

# After an upgrade, restart a service installed earlier so it runs the new binary.
restart_existing_service() {
  if [ -f "$SYSTEMD_UNIT" ] && command -v systemctl >/dev/null 2>&1; then
    if systemctl --user restart "$BIN"; then say "Restarted the $BIN service"; else warn "could not restart the $BIN service"; fi
  elif [ -f "$LAUNCHD_PLIST" ]; then
    if launchctl kickstart -k "gui/$(id -u)/$LAUNCHD_LABEL"; then say "Restarted the $BIN service"; else warn "could not restart the $BIN service"; fi
  fi
}

uninstall() {
  if [ -f "$SYSTEMD_UNIT" ]; then
    systemctl --user disable --now "$BIN" >/dev/null 2>&1 || true
    rm -f "$SYSTEMD_UNIT"
    systemctl --user daemon-reload 2>/dev/null || true
    say "Removed $SYSTEMD_UNIT"
  fi
  if [ -f "$LAUNCHD_PLIST" ]; then
    launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
    rm -f "$LAUNCHD_PLIST"
    say "Removed $LAUNCHD_PLIST"
  fi

  if [ -e "$INSTALL_DIR/$BIN" ]; then
    rm -f "$INSTALL_DIR/$BIN"
    say "Removed $INSTALL_DIR/$BIN"
  else
    other=$(command -v "$BIN" 2>/dev/null || true)
    if [ -n "$other" ]; then
      warn "no $BIN in $INSTALL_DIR, but found $other; rerun with --dir $(dirname "$other")"
    else
      say "$BIN is not installed in $INSTALL_DIR"
    fi
  fi

  if [ "$PURGE" = 1 ]; then
    case "$DATA_DIR" in
      "" | / | "$HOME" | "$HOME/") die "refusing to delete data directory '$DATA_DIR'" ;;
    esac
    rm -rf "$DATA_DIR"
    say "Removed $DATA_DIR"
  elif [ -d "$DATA_DIR" ]; then
    say "Kept your settings in $DATA_DIR (add --purge to delete them)"
  fi
}

main() {
  VERSION="${VERSION:-latest}"
  INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
  ACTION=install
  SERVICE=0
  PURGE=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --version) [ $# -ge 2 ] || die "--version needs a value"; VERSION=$2; shift ;;
      --version=*) VERSION=${1#*=} ;;
      --dir) [ $# -ge 2 ] || die "--dir needs a value"; INSTALL_DIR=$2; shift ;;
      --dir=*) INSTALL_DIR=${1#*=} ;;
      --service) SERVICE=1 ;;
      --uninstall) ACTION=uninstall ;;
      --purge) PURGE=1 ;;
      -h | --help) usage; exit 0 ;;
      *) usage >&2; die "unknown option: $1" ;;
    esac
    shift
  done
  [ "$PURGE" = 0 ] || [ "$ACTION" = uninstall ] || die "--purge only works together with --uninstall"
  case "$INSTALL_DIR" in
    /*) ;;
    *) INSTALL_DIR="$(pwd)/$INSTALL_DIR" ;;
  esac

  if [ "$ACTION" = uninstall ]; then
    uninstall
    return
  fi

  install_binary
  if [ "$SERVICE" = 1 ]; then
    install_service
  else
    restart_existing_service
  fi
  report_clis
  say ""
  if [ "$SERVICE" = 1 ]; then
    say "Dashboard: http://127.0.0.1:8787/ (or the port set in $DATA_DIR/config.json)"
  else
    say "Start it with '$BIN', then open http://127.0.0.1:8787/"
  fi
}

# Everything runs from main, so a partially downloaded script does nothing.
main "$@"
