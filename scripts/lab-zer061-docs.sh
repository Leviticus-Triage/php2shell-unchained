#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$ROOT/third_party/zer061-php2shell"
ACTION="${1:-list}"
NAME="${2:-}"

if [[ ! -d "$KIT" ]]; then
  echo "FEHLER: $KIT fehlt — fetch-zer061" >&2
  exit 1
fi

mapfile -t DOCS < <(find "$KIT" -maxdepth 1 -name '*.md' -type f | sort)

case "$ACTION" in
  list)
    echo "Zer061 Kit — Analyse-Dokumente ($KIT):"
    for f in "${DOCS[@]}"; do
      echo "  $(basename "$f")"
    done
    echo
    echo "Lesen: $0 open HTTP_HEAP_LEAK.md   (oder \$PAGER)"
    ;;
  open|show|cat)
    if [[ -z "$NAME" ]]; then
      echo "Usage: $0 open <DATEI.md>" >&2
      exit 2
    fi
    path="$KIT/$NAME"
    [[ -f "$path" ]] || path="$(find "$KIT" -maxdepth 1 -name "*$NAME*" -type f | head -1)"
    if [[ ! -f "$path" ]]; then
      echo "Nicht gefunden: $NAME" >&2
      exit 1
    fi
    if [[ -n "${PAGER:-}" ]]; then
      "$PAGER" "$path"
    elif command -v less >/dev/null; then
      less "$path"
    else
      cat "$path"
    fi
    ;;
  path)
    printf '%s\n' "${DOCS[@]}"
    ;;
  *)
    echo "Usage: $0 list|open <file>|path" >&2
    exit 2
    ;;
esac
