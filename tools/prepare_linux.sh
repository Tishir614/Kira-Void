#!/usr/bin/env bash
# Prepares android_app/ for a Linux desktop build: removes the phone-only on-device
# LLM plugin (it downloads a JRE at build time) and sets the window title.
set -euo pipefail
cd "$(dirname "$0")/../android_app"
sed -i '/^  flutter_gemma:/d' pubspec.yaml
cp linux_overrides/local_ai.dart lib/local_ai.dart
flutter create --org com.kiravoid --project-name kira_void --platforms linux .
sed -i 's/"kira_void")/"Kira-Void")/' linux/runner/my_application.cc
sed -i 's/gtk_window_set_default_size(window, 1280, 720)/gtk_window_set_default_size(window, 1000, 760)/' linux/runner/my_application.cc
