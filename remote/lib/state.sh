# shellcheck shell=bash
# Incremental engagement state. One session dir per run; phases are idempotent
# and write <phase>.done + <phase>.env. Later phases source all earlier envs,
# which is what chains recon → fingerprint → exploit → foothold → post-ex.

state_init() {
  # state_init <session-id> → exports ENGAGE_DIR, ENGAGE_STATE
  local sid="$1"
  ENGAGE_DIR="$LAB_ROOT/out/engage/$sid"
  ENGAGE_STATE="$ENGAGE_DIR/state"
  mkdir -p "$ENGAGE_STATE" "$ENGAGE_DIR/logs"
  export ENGAGE_DIR ENGAGE_STATE
}

state_done()    { [[ -f "$ENGAGE_STATE/$1.done" ]]; }
state_mark()    { date -u +%Y-%m-%dT%H:%M:%SZ > "$ENGAGE_STATE/$1.done"; }
state_set()     { printf '%q' "$3" > "$ENGAGE_STATE/$1.env.$2"; }
state_get()     { cat "$ENGAGE_STATE/$1.env.$2" 2>/dev/null || true; }

# Source every <phase>.env.<key> from earlier phases into the environment.
state_hydrate() {
  local f
  for f in "$ENGAGE_STATE"/*.env.*; do
    [[ -f "$f" ]] || continue
    local base; base="$(basename "$f")"       # phase.env.KEY
    local key="${base##*.}"
    printf -v "$key" '%s' "$(cat "$f")"
    export "$key"
  done
}

state_resume_report() {
  local f
  for f in "$ENGAGE_STATE"/*.done; do
    [[ -f "$f" ]] || continue
    printf '  ✓ %-14s (%s)\n' "$(basename "$f" .done)" "$(cat "$f")"
  done
}
