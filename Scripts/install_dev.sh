#!/usr/bin/env bash
set -euo pipefail

# Developer setup for NagaController
# - Ensures Swift toolchain available
# - Prints instructions

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift toolchain not found. Install Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

chmod +x "$(dirname "$0")/build_app.sh"

cat <<'EOT'
NagaController - Developer Setup
--------------------------------
Build (Debug):
  swift build

Build app bundle (Release):
  Scripts/build_app.sh

Run executable (Debug):
  .build/debug/NagaController

Grant Accessibility:
  On first run, macOS will prompt for Accessibility permissions.
  System Settings → Privacy & Security → Accessibility → enable NagaController.
EOT
