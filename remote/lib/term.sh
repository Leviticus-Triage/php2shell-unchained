# shellcheck shell=bash
# Multi-terminal spawner. One listener/console/log job per pane or window.
# Backends (auto-detect, override with ENGAGE_TERMINAL=tmux|gnome|none):
#   tmux   — detached session, one window per job, survives menu exit
#   gnome  — gnome-terminal tabs on the local desktop
#   none   — nohup background jobs + log files (headless / SSH)

term_backend() {
  local pref="${ENGAGE_TERMINAL:-auto}"
  if [[ "$pref" != "auto" ]]; then printf '%s' "$pref"; return; fi
  if command -v tmux >/dev/null 2>&1; then printf 'tmux'; return; fi
  if command -v gnome-terminal >/dev/null 2>&1; then printf 'gnome'; return; fi
  if command -v konsole >/dev/null 2>&1; then printf 'konsole'; return; fi
  if command -v kitty >/dev/null 2>&1; then printf 'kitty'; return; fi
  if command -v xterm >/dev/null 2>&1; then printf 'xterm'; return; fi
  printf 'none'
}

# term_spawn_jobs <session-name> <logdir> <name=cmd> [name=cmd …]
# Each job spec: "name|command string". Runs every command in its own pane.
term_spawn_jobs() {
  local session="$1" logdir="$2"; shift 2
  local backend; backend="$(term_backend)"
  mkdir -p "$logdir"
  echo "[term] Backend: $backend · Session: $session · $# Job(s)"

  case "$backend" in
    tmux)
      tmux kill-session -t "$session" 2>/dev/null || true
      tmux new-session -d -s "$session" -x 220 -y 50
      local first=1 spec name cmd
      for spec in "$@"; do
        name="${spec%%|*}"; cmd="${spec#*|}"
        local wrapped="cd '$LAB_ROOT' && { $cmd ; } 2>&1 | tee '$logdir/$name.log'; echo; echo '[job $name beendet]'; exec bash"
        if [[ $first -eq 1 ]]; then
          tmux rename-window -t "$session:0" "$name"
          tmux send-keys -t "$session:0" "$wrapped" C-m
          first=0
        else
          tmux new-window -t "$session" -n "$name"
          tmux send-keys -t "$session" "$wrapped" C-m
        fi
      done
      echo "[term] Attach:  tmux attach -t $session"
      echo "[term] Fenster: tmux list-windows -t $session"
      ;;
    gnome)
      local args=(--window) spec name cmd
      for spec in "$@"; do
        name="${spec%%|*}"; cmd="${spec#*|}"
        args+=(--tab --title="$name" -- bash -c "cd '$LAB_ROOT' && { $cmd ; } 2>&1 | tee '$logdir/$name.log'; exec bash")
      done
      gnome-terminal "${args[@]}" 2>/dev/null &
      echo "[term] gnome-terminal mit $# Tabs gestartet."
      ;;
    konsole|kitty|xterm)
      local spec name cmd
      for spec in "$@"; do
        name="${spec%%|*}"; cmd="${spec#*|}"
        case "$backend" in
          konsole) konsole --new-tab -e bash -c "cd '$LAB_ROOT' && $cmd 2>&1 | tee '$logdir/$name.log'; exec bash" & ;;
          kitty)   kitty --title "$name" bash -c "cd '$LAB_ROOT' && $cmd 2>&1 | tee '$logdir/$name.log'; exec bash" & ;;
          xterm)   xterm -T "$name" -e bash -c "cd '$LAB_ROOT' && $cmd 2>&1 | tee '$logdir/$name.log'; exec bash" & ;;
        esac
      done
      ;;
    none)
      local spec name cmd
      for spec in "$@"; do
        name="${spec%%|*}"; cmd="${spec#*|}"
        ( cd "$LAB_ROOT" && nohup bash -c "$cmd" >"$logdir/$name.log" 2>&1 & echo $! >"$logdir/$name.pid" )
        echo "[term] nohup: $name (pid $(cat "$logdir/$name.pid"), log $logdir/$name.log)"
      done
      ;;
  esac
}
