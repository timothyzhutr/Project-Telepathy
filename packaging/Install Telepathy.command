#!/bin/bash
set -euo pipefail
telepathy_source="$(cd "$(dirname "$0")" && pwd)/Telepathy.app"
telepathy_install_root="${TELEPATHY_INSTALL_ROOT:-$HOME}"
telepathy_target="$telepathy_install_root/Library/Input Methods/Telepathy.app"
telepathy_profile="$telepathy_install_root/Library/Telepathy/Rime"
telepathy_backup_root="$telepathy_install_root/Library/Application Support/Telepathy/InstallBackups"
if [[ ! -x "$telepathy_source/Contents/MacOS/Telepathy" ]]; then
  echo 'Keep this installer beside Telepathy.app.'; exit 1
fi
mkdir -p "$telepathy_install_root/Library/Input Methods" "$telepathy_backup_root" "$(dirname "$telepathy_profile")"
telepathy_backup=$(mktemp -d "$telepathy_backup_root/$(date +%Y%m%d-%H%M%S)-XXXXXX")
: > "$telepathy_backup/.install-in-progress"
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
  # Older native releases did not stop their helper on quit. Stop only this
  # user's helper at the installation being replaced, never a development app.
  telepathy_worker="$telepathy_target/Contents/Helpers/TelepathyWorker.app/Contents/MacOS/TelepathyWorker"
  telepathy_workers=""
  while read -r telepathy_pid telepathy_command; do
    case "$telepathy_command" in
      "$telepathy_worker --serve"|"$telepathy_worker --serve "*)
        telepathy_workers="$telepathy_workers $telepathy_pid"
        kill -TERM "$telepathy_pid" 2>/dev/null || true
        ;;
    esac
  done < <(/bin/ps -ww -U "$(id -u)" -o pid= -o command=)
  for telepathy_pid in $telepathy_workers; do
    telepathy_exited=false
    for ((telepathy_attempt=0; telepathy_attempt<100; telepathy_attempt++)); do
      telepathy_state=$(/bin/ps -p "$telepathy_pid" -o state= 2>/dev/null || true)
      if [[ -z "$telepathy_state" || "$telepathy_state" == *Z* ]]; then
        telepathy_exited=true; break
      fi
      sleep 0.1
    done
    if ! $telepathy_exited; then
      echo 'The previous model helper is still stopping. Please retry installation.'
      false
    fi
  done
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
rm "$telepathy_backup/.install-in-progress"
trap - ERR
# Retain the two newest completed backups. Leave failed/staged installs and
# unrelated folders alone; pruning happens only after installation succeeds.
telepathy_retained=0
if $telepathy_moved_app || $telepathy_moved_profile; then telepathy_retained=1; fi
while IFS= read -r telepathy_old; do
  [[ -d "$telepathy_old" && ! -L "$telepathy_old" ]] || continue
  telepathy_name=${telepathy_old##*/}
  [[ "$telepathy_name" =~ ^[0-9]{8}-[0-9]{6}(-[A-Za-z0-9]+)?$ ]] || continue
  [[ "$telepathy_old" != "$telepathy_backup" ]] || continue
  [[ ! -e "$telepathy_old/new.app" && ! -e "$telepathy_old/.install-in-progress" ]] || continue
  [[ -d "$telepathy_old/Telepathy.app" || -d "$telepathy_old/Rime" ]] || continue
  telepathy_retained=$((telepathy_retained+1))
  if ((telepathy_retained > 2)); then rm -rf "$telepathy_old"; fi
done < <(LC_ALL=C /bin/ls -dt "$telepathy_backup_root"/*)
if ! "$telepathy_target/Contents/MacOS/Telepathy" --verify-input-source; then
  echo 'In System Settings → Keyboard → Text Input → Edit → +, search Telepathy and Add it.'
  open 'x-apple.systempreferences:com.apple.Keyboard-Settings.extension'
fi
echo 'Installed. Select Telepathy in the input-source menu. Log out and back in if it is missing.'
echo 'For Kev assistance run:'
printf '"%s" --download-model\n' "$telepathy_target/Contents/MacOS/Telepathy"
printf 'Previous installation, if any: %s\n' "$telepathy_backup"
