#!/usr/bin/env bash
# Ally DSP installer: downloads the latest release, verifies checksum and
# signature, installs into ~/homebrew/plugins/Ally DSP.
#   curl -sL https://github.com/bassobr/decky-ally-dsp/raw/main/install.sh -o /tmp/ally-dsp-install.sh && sudo bash /tmp/ally-dsp-install.sh
# Set ALLY_DSP_REPO=owner/repo to install the latest release of a fork.
set -euo pipefail
PLUGIN_NAME="Ally DSP"
REPO="${ALLY_DSP_REPO:-bassobr/decky-ally-dsp}"
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo: sudo bash $0" >&2; exit 1
fi
DECK_USER="${SUDO_USER:-$(logname 2>/dev/null || echo deck)}"
USER_HOME="$(getent passwd "$DECK_USER" | cut -d: -f6)"; USER_HOME="${USER_HOME:-/home/$DECK_USER}"
PLUGIN_BASE="$USER_HOME/homebrew/plugins"
[ -d "$PLUGIN_BASE" ] || { echo "Decky Loader not found at $PLUGIN_BASE. Install it first: https://decky.xyz" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "Looking up the latest release..."
TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
[ -n "$TAG" ] || { echo "Could not determine the latest release" >&2; exit 1; }
VERSION="${TAG#v}"; ZIP="ally-dsp-$VERSION.zip"; BASE="https://github.com/$REPO/releases/download/$TAG"
echo "Downloading $ZIP ($TAG)..."
curl -fsSL -o "$TMP/$ZIP" "$BASE/$ZIP"
curl -fsSL -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS"
curl -fsSL -o "$TMP/SHA256SUMS.minisig" "$BASE/SHA256SUMS.minisig" || echo "warning: release has no signature file"
EXPECTED="$(grep " \*\?$ZIP\$" "$TMP/SHA256SUMS" | head -1 | cut -d' ' -f1)"
ACTUAL="$(sha256sum "$TMP/$ZIP" | cut -d' ' -f1)"
[ -n "$EXPECTED" ] && [ "$EXPECTED" = "$ACTUAL" ] || { echo "Checksum mismatch for $ZIP" >&2; exit 1; }
echo "Checksum OK. Extracting..."
mkdir -p "$TMP/x"
if command -v bsdtar >/dev/null 2>&1; then bsdtar -xf "$TMP/$ZIP" -C "$TMP/x"; else python3 -c "import sys,zipfile;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$TMP/$ZIP" "$TMP/x"; fi
[ -f "$TMP/x/$PLUGIN_NAME/plugin.json" ] || { echo "Unexpected zip layout" >&2; exit 1; }
if [ -f "$TMP/SHA256SUMS.minisig" ] && [ -f "$TMP/x/$PLUGIN_NAME/minisign.pub" ]; then
  if PYTHONPATH="$TMP/x/$PLUGIN_NAME/py_modules" python3 -m allydsp.minisign verify "$TMP/SHA256SUMS" "$TMP/SHA256SUMS.minisig" "$TMP/x/$PLUGIN_NAME/minisign.pub"; then
    echo "Signature OK."
  else
    echo "Release signature INVALID, aborting." >&2; exit 1
  fi
fi
rm -rf "$PLUGIN_BASE/$PLUGIN_NAME"
mv "$TMP/x/$PLUGIN_NAME" "$PLUGIN_BASE/$PLUGIN_NAME"
chown -R "$DECK_USER:$DECK_USER" "$PLUGIN_BASE/$PLUGIN_NAME"
systemctl restart plugin_loader 2>/dev/null || true
echo "Installed $PLUGIN_NAME $VERSION. Open the Quick Access menu, Decky tab, Ally DSP, and run the setup."
