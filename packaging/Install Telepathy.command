#!/bin/bash
set -euo pipefail
telepathy_source="$(cd "$(dirname "$0")" && pwd)/Telepathy.app"
telepathy_install_root="${TELEPATHY_INSTALL_ROOT:-$HOME}"
telepathy_target="$telepathy_install_root/Library/Input Methods/Telepathy.app"
telepathy_profile="$telepathy_install_root/Library/Telepathy/Rime"
telepathy_backup="$telepathy_install_root/Library/Application Support/Telepathy/InstallBackups/$(date +%Y%m%d-%H%M%S)"
if [[ ! -x "$telepathy_source/Contents/MacOS/Telepathy" ]]; then
  echo 'Keep this installer beside Telepathy.app.'; exit 1
fi
mkdir -p "$telepathy_install_root/Library/Input Methods" "$telepathy_backup" "$(dirname "$telepathy_profile")"
# Stage the new app before touching the existing installation.
telepathy_stage="$telepathy_backup/new.app"
ditto "$telepathy_source" "$telepathy_stage"
telepathy_moved_app=false
telepathy_moved_profile=false
telepathy_installed_app=false
telepathy_created_profile=false
telepathy_rollback() {
  echo 'Installation failed; restoring the previous installation.'
  if $telepathy_installed_app; then rm -rf "$telepathy_target"; fi
  if $telepathy_created_profile; then rm -rf "$telepathy_profile"; fi
  if $telepathy_moved_app; then mv "$telepathy_backup/Telepathy.app" "$telepathy_target"; fi
  if $telepathy_moved_profile; then mv "$telepathy_backup/Rime" "$telepathy_profile"; fi
}
trap telepathy_rollback ERR
if [[ -d "$telepathy_target" ]]; then
  "$telepathy_target/Contents/MacOS/Telepathy" --quit || true
  mv "$telepathy_target" "$telepathy_backup/Telepathy.app"
  telepathy_moved_app=true
fi
if [[ -d "$telepathy_profile" ]]; then
  mv "$telepathy_profile" "$telepathy_backup/Rime"
  telepathy_moved_profile=true
fi
mv "$telepathy_stage" "$telepathy_target"
telepathy_installed_app=true
telepathy_created_profile=true
ditto "$telepathy_target/Contents/Resources/Profile" "$telepathy_profile"
"$telepathy_target/Contents/MacOS/Telepathy" --verify-runtime
"$telepathy_target/Contents/MacOS/Telepathy" --register-input-source
"$telepathy_target/Contents/MacOS/Telepathy" --enable-input-source
trap - ERR
if ! "$telepathy_target/Contents/MacOS/Telepathy" --verify-input-source; then
  echo 'In System Settings → Keyboard → Text Input → Edit → +, search Telepathy and Add it.'
  open 'x-apple.systempreferences:com.apple.Keyboard-Settings.extension'
fi
echo 'Installed. Select Telepathy in the input-source menu. Log out and back in if it is missing.'
echo 'For Kev assistance run:'
printf '"%s" --download-model\n' "$telepathy_target/Contents/MacOS/Telepathy"
printf 'Previous installation, if any: %s\n' "$telepathy_backup"
