#!/usr/bin/env bash
# Multi-terminal convenience for the ISOLATED LAB workflow.
# Spawns tmux panes for stack/logs/monitor/audit. Lab commands only —
# takes no target argument and is not an attack executor.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACTION="${1:-lab}"
W="$ROOT/bin/vtbw-php2shell-lab"
SESSION="p2s-lab"

usage() {
  cat <<EOF
session — tmux panes for the isolated lab (parallel windows)

  $0 lab      4 panes: [1] target up  [2] logs target  [3] audit list  [4] monitor
  $0 audit    3 panes: [1] workarounds run  [2] logs  [3] shell
  $0 down     close tmux session

Requires tmux. Scope: compose lab only. For real hosts see docs/AUTHORIZED-ASSESSMENT.md.
EOF
}

need_tmux() {
  command -v tmux >/dev/null 2>&1 || { echo "FEHLER: tmux fehlt (apt install tmux)"; exit 1; }
}

case "$ACTION" in
  help|-h|--help) usage ;;
  lab)
    need_tmux
    tmux has-session -t "$SESSION" 2>/dev/null && { tmux attach -t "$SESSION"; exit 0; }
    tmux new-session -d -s "$SESSION" -n lab -x 220 -y 50 \
      "cd '$ROOT' && '$W' up && echo && echo '[pane 1] stack up — Enter für Shell' && bash"
    tmux split-window -h -t "$SESSION:lab" \
      "cd '$ROOT' && sleep 3 && '$W' logs target"
    tmux split-window -v -t "$SESSION:lab.0" \
      "cd '$ROOT' && '$W' patch-audit list && echo && echo '[pane 3] audit list — bereit' && bash"
    tmux split-window -v -t "$SESSION:lab.1" \
      "cd '$ROOT' && sleep 5 && '$W' doctor && echo && echo '[pane 4] doctor — bereit' && bash"
    tmux select-layout -t "$SESSION:lab" tiled
    echo "tmux session '$SESSION': attach via 'tmux attach -t $SESSION'"
    [[ -t 0 && -z "${TMUX:-}" ]] && exec tmux attach -t "$SESSION"
    ;;
  audit)
    need_tmux
    tmux has-session -t "$SESSION" 2>/dev/null && { tmux attach -t "$SESSION"; exit 0; }
    tmux new-session -d -s "$SESSION" -n audit -x 220 -y 50 \
      "cd '$ROOT' && '$W' workarounds run"
    tmux split-window -h -t "$SESSION:audit" \
      "cd '$ROOT' && '$W' logs target"
    tmux split-window -v -t "$SESSION:audit.0" \
      "cd '$ROOT' && echo '[pane 3] freie Shell — Auswertung: workarounds last' && bash"
    tmux select-layout -t "$SESSION:audit" tiled
    echo "tmux session '$SESSION': attach via 'tmux attach -t $SESSION'"
    [[ -t 0 && -z "${TMUX:-}" ]] && exec tmux attach -t "$SESSION"
    ;;
  down)
    need_tmux
    tmux kill-session -t "$SESSION" 2>/dev/null && echo "Session '$SESSION' geschlossen." || echo "Keine Session."
    ;;
  *)
    echo "Unbekannt: $ACTION" >&2; usage; exit 2 ;;
esac
