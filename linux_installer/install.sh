#!/usr/bin/env bash
# Kira-Void installer for Linux: app + local AI server (Qwen via Ollama, optional SDXL images).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.local/share/kira-void"
BIN="$HOME/.local/bin"
CONF="$HOME/.config/kira-void"

say() { printf '\n\033[1;35m▸ %s\033[0m\n' "$*"; }
ask() { local a; read -r -p "$1 [y/N] " a </dev/tty || true; [[ "$a" =~ ^[YyДд] ]]; }

say "Устанавливаю Kira-Void в $DEST"
mkdir -p "$DEST" "$BIN" "$CONF" "$HOME/.local/share/applications"
rm -rf "$DEST/app" "$DEST/server"
cp -r "$SRC/app" "$SRC/server" "$DEST/"
cp "$SRC/icon.png" "$SRC/uninstall.sh" "$DEST/"
chmod +x "$DEST/app/kira_void" "$DEST/uninstall.sh"

if ! command -v ollama >/dev/null; then
  say "Ollama не найдена — ставлю (нужен пароль sudo)"
  curl -fsSL https://ollama.com/install.sh | sh
fi

say "Python-окружение для сервера"
python3 -m venv "$DEST/venv"
"$DEST/venv/bin/pip" install -q --upgrade pip
if ask "Установить генерацию картинок (SDXL, нужна видеокарта NVIDIA, ~6 ГБ)?"; then
  "$DEST/venv/bin/pip" install torch diffusers transformers accelerate safetensors pillow
fi

say "Какую модель Qwen для чата поставить?"
echo "  1) default    qwen3:8b       — 8 ГБ ОЗУ/видеопамяти"
echo "  2) smart      qwen3:14b      — нужно ~12 ГБ"
echo "  3) uncensored qwen3 8b без отказов (community)"
read -r -p "Номер [1]: " n </dev/tty || n=1
case "${n:-1}" in 2) preset=smart ;; 3) preset=uncensored ;; *) preset=default ;; esac
pgrep -x ollama >/dev/null || (ollama serve >/dev/null 2>&1 &) ; sleep 2
base=$("$DEST/venv/bin/python" -c "import sys;sys.path.insert(0,'$DEST/server');import kira_void as k;print(k.PRESETS['$preset'])")
ollama pull "$base"
(cd "$DEST/server" && "$DEST/venv/bin/python" kira_void.py setup "$preset")

[ -f "$CONF/env" ] || cat > "$CONF/env" <<'CFG'
# Kira-Void settings (read by the kira-void launcher)
# KIRA_IMAGE_MODEL=/path/to/model.safetensors   # e.g. OrbitMixV2.1.safetensors or any SDXL checkpoint
# KIRA_LOWVRAM=1                                # GPUs with less than ~16 GB
# KIRA_REFINER=none
CFG

cat > "$BIN/kira-void" <<LAUNCH
#!/usr/bin/env bash
# Starts Ollama and the Kira-Void server if needed, then opens the app.
set -a; [ -f "$CONF/env" ] && . "$CONF/env"; set +a
pgrep -x ollama >/dev/null || (ollama serve >/dev/null 2>&1 &)
started=""
if ! curl -s -o /dev/null http://127.0.0.1:8080/ping; then
  (cd "$DEST/server" && exec "$DEST/venv/bin/python" kira_void.py web) >"$CONF/server.log" 2>&1 &
  started=\$!
  for _ in \$(seq 50); do curl -s -o /dev/null http://127.0.0.1:8080/ping && break; sleep 0.2; done
fi
"$DEST/app/kira_void" "\$@"
[ -n "\$started" ] && kill "\$started" 2>/dev/null || true
LAUNCH
chmod +x "$BIN/kira-void"

cat > "$HOME/.local/share/applications/kira-void.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Kira-Void
Comment=Local AI: chat and images
Exec=$BIN/kira-void
Icon=$DEST/icon.png
Terminal=false
Categories=Utility;Graphics;Chat;
DESK
update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

say "Готово! Kira-Void есть в меню приложений, или запусти командой: kira-void"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "(добавь $BIN в PATH, чтобы команда kira-void работала в терминале)";; esac
