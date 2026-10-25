#!/usr/bin/env bash
# Verlinkt die Lab-Befehle nach ~/.local/bin und, falls schreibbar, /usr/local/bin.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
chmod +x "$ROOT/bin/vtbw-php2shell-lab" "$ROOT/bin/php2shell-unchained" "$ROOT/bin/vtbw-php2shell-doctor"

link_into() {
  local dest="$1"
  mkdir -p "$dest"
  ln -sfn "$ROOT/bin/vtbw-php2shell-lab" "$dest/vtbw-php2shell-lab"
  ln -sfn "$ROOT/bin/php2shell-unchained" "$dest/php2shell-unchained"
  ln -sfn "$ROOT/bin/vtbw-php2shell-doctor" "$dest/vtbw-php2shell-doctor"
  echo "[install] $dest"
  echo "  vtbw-php2shell-lab -> $ROOT/bin/vtbw-php2shell-lab"
  echo "  php2shell-unchained -> $ROOT/bin/php2shell-unchained"
  echo "  vtbw-php2shell-doctor -> $ROOT/bin/vtbw-php2shell-doctor"
}

link_into "${HOME}/.local/bin"

if [[ -w /usr/local/bin ]]; then
  link_into /usr/local/bin
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo mkdir -p /usr/local/bin
  sudo ln -sfn "$ROOT/bin/vtbw-php2shell-lab" /usr/local/bin/vtbw-php2shell-lab
  sudo ln -sfn "$ROOT/bin/php2shell-unchained" /usr/local/bin/php2shell-unchained
  sudo ln -sfn "$ROOT/bin/vtbw-php2shell-doctor" /usr/local/bin/vtbw-php2shell-doctor
  echo "[install] /usr/local/bin (sudo)"
else
  echo "[install] /usr/local/bin übersprungen (kein Schreibrecht, sudo -n nicht verfügbar)"
fi

# Alte Geschwister-Launcher im cursor-projects-Ordner auf die Repo-Skripte zeigen lassen.
PARENT="$(dirname "$ROOT")"
if [[ -d "$PARENT" && "$PARENT" != "$ROOT" ]]; then
  ln -sfn "$ROOT/bin/vtbw-php2shell-lab" "$PARENT/vtbw-php2shell-lab"
  ln -sfn "$ROOT/bin/php2shell-unchained" "$PARENT/php2shell-unchained"
  ln -sfn "$ROOT/bin/vtbw-php2shell-doctor" "$PARENT/vtbw-php2shell-doctor"
  echo "[install] $PARENT (alte Launcher ersetzt)"
fi

echo
echo "Aufruf aus jedem Verzeichnis, sobald ~/.local/bin im PATH liegt:"
echo "  vtbw-php2shell-lab help"
echo "  php2shell-unchained"
echo "  vtbw-php2shell-doctor"
