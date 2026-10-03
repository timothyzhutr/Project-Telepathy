#!/bin/bash
set -euo pipefail
telepathy_app="$HOME/Library/Input Methods/Telepathy.app/Contents/MacOS/Telepathy"
if [[ ! -x "$telepathy_app" ]]; then
  telepathy_app="$(cd "$(dirname "$0")" && pwd)/Telepathy.app/Contents/MacOS/Telepathy"
fi
"$telepathy_app" --download-model
