# Remote engagement mode (authorized production hosts)

The compose lab proves the chains in isolation. Security teams also need to run the **same chain** against a real deployment they are **authorized** to test — staging, pre-prod, or a production system covered by written Rules of Engagement. That is what `engage` does.

The probes-only variant (no chaining, no C2) stays in [docs/AUTHORIZED-ASSESSMENT.md](../docs/AUTHORIZED-ASSESSMENT.md) (`assess`). `engage` is the full-chain sibling with the **same scope gate plus an explicit confirmation**.

## Gate (non-negotiable)

Two conditions, enforced by every phase:

1. `scope-authorized.txt` in the repo root contains the target host (exact name, `.domain` suffix, or IPv4 CIDR), ideally with the RoE ticket as a comment.
2. `CONFIRM_ROE=I-AM-AUTHORIZED` in the environment.

No scope entry → exit 3 before the first packet. No confirmation → exit 4 before exploit/post-ex phases.

## Phase chain (incremental + resume)

```text
00 scope ──► 10 recon ──► 20 fingerprint ──► 30 exploit
      │           │              │                 │
      │           │              │                 ▼
      │           │              │          40 foothold (listener terminal)
      │           │              │                 │
      │           │              │                 ▼
      │           │              │          50 post-ex (C2 / console terminals)
      │           │              │                 │
      ▼           ▼              ▼                 ▼
              60 report  ◄── state envs chain every phase together
```

- Each phase writes `out/engage/<sid>/state/<phase>.done` and exports its results (`state/<phase>.env.*`).
- Later phases **hydrate** earlier results (server banner → exploit choice, listener address → post-ex).
- Re-running skips finished phases. `engage resume <sid>` continues an interrupted run.

## Multi-terminal spawning

Phases that need parallel windows (foothold listener, Sliver server/listener/console, log tails) spawn them automatically — one window or pane per job:

| Backend | Detection | Behaviour |
|---------|-----------|-----------|
| `tmux` | preferred | detached session `p2s-<sid>`, one window per job, `tmux attach -t p2s-<sid>` |
| `gnome` | fallback | one `gnome-terminal` window, tab per job |
| `konsole`/`kitty`/`xterm` | fallback | window per job |
| `none` | headless | `nohup` jobs + `logs/<name>.log` + pid files |

Override: `ENGAGE_TERMINAL=tmux|gnome|none`.

## Quick start (authorized staging host)

```bash
# 1. Declare RoE scope (gitignored file)
echo 'staging-php.customer-internal.example  # RoE SEC-1234' >> scope-authorized.txt

# 2. Run the full chain (incremental; safe to re-run)
CONFIRM_ROE=I-AM-AUTHORIZED \
ENGAGE_LHOST=10.20.30.40 \
vtbw-php2shell-lab engage run 'https://staging-php.customer-internal.example/index.php'

# 3. Optional profiles
ENGAGE_TOR=on           # recon/probes via local Tor (127.0.0.1:9050)
ENGAGE_C2=sliver        # post-ex profile with Sliver terminals

# 4. Later
vtbw-php2shell-lab engage resume 20261102-090015
vtbw-php2shell-lab engage status
vtbw-php2shell-lab engage listeners 20261102-090015   # re-spawn listener windows
```

Artifacts: `out/engage/<sid>/` — `ENGAGEMENT.md`, `REPORT.md`, `logs/` per phase, terminal job logs.

## What this mode deliberately reuses

| Component | Source |
|-----------|--------|
| FPM PoC chain | `attacker/scripts/php2shell_poc.py` (public research, same as lab) |
| mod_php kit | Zer061 bundle via `fetch-zer061` (public PoC) |
| Fingerprint probes | `patch_audit.py` non-destructive scenarios |
| C2 profile | BishopFox Sliver (public; `fetch-sliver`) |
| Reverse-channel variants | lukechilds/reverse-shell slot |
| Tor egress | existing `lab-tor.sh` sidecar |

Nothing new is invented here — the mode **orchestrates** the lab's public components against a scoped target and keeps evidence in one session directory.

## Operator checklist (production window)

- [ ] Written RoE covers exploit chaining and post-exploitation, not just probes
- [ ] Change window and rollback plan agreed with the system owner
- [ ] `ENGAGE_LHOST` is reachable from the target (firewall/security groups)
- [ ] SOC/monitoring team informed (or deliberately not — purple team decision, document it)
- [ ] `engage resume` tested once before the window (state hydration works)
- [ ] After: `REPORT.md` archived with the RoE ticket; implants and listeners removed
