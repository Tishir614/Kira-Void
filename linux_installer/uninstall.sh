#!/usr/bin/env bash
# Removes Kira-Void (keeps Ollama, its models and ~/.kira-void history).
rm -rf "$HOME/.local/share/kira-void" "$HOME/.local/bin/kira-void" \
       "$HOME/.local/share/applications/kira-void.desktop" "$HOME/.config/kira-void"
echo "Kira-Void удалён. Модели Ollama удаляются командой: ollama rm kira-void"
