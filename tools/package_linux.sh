#!/usr/bin/env bash
# Packs the built Linux app, the server and the installer into kira-void-linux.tar.gz.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist/kira-void"
rm -rf "$ROOT/dist" && mkdir -p "$OUT/server"
cp -r "$ROOT/android_app/build/linux/x64/release/bundle" "$OUT/app"
cp -r "$ROOT/kira_void.py" "$ROOT/images.py" "$ROOT/Modelfile" "$ROOT/web" "$OUT/server/"
cp "$ROOT/android_app/assets/icon.png" "$ROOT/linux_installer/install.sh" "$ROOT/linux_installer/uninstall.sh" "$OUT/"
chmod +x "$OUT/install.sh" "$OUT/uninstall.sh"
tar -C "$ROOT/dist" -czf "$ROOT/kira-void-linux.tar.gz" kira-void
echo "kira-void-linux.tar.gz: $(du -h "$ROOT/kira-void-linux.tar.gz" | cut -f1)"
