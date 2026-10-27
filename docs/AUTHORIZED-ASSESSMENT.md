# Authorized assessment mode (your own servers, not just the lab)

The compose lab proves concepts. Operators also need to know whether a **real** PHP deployment (their own staging, a customer system with written Rules of Engagement) holds the mitigations. This mode exists for exactly that — with an explicit scope gate.

## What this mode does and does not do

| Does | Does not |
|------|----------|
| Send the 11 patch / WAF audit probes to a host you authorize | Exploit-chain to shell on that host |
| Measure whether a mitigation (version, ini, WAF, edge rule) blocks the attack path | Deploy implants, C2, or post-exploitation on it |
| Write JSONL evidence + markdown report | Obfuscate origin by default (Tor stays an explicit lab option, not the assessment default) |
| Refuse to run without a scope file | Run against arbitrary IPs |

This is deliberate. The delta between "validation tool" and "attack framework" is not the probe — it is chaining, payload delivery, and origin hiding. For engagements where the RoE **does** cover the full chain against your production systems, use the additionally gated mode: [remote/README.md](../remote/README.md) (`engage` — same scope file **plus** `CONFIRM_ROE=I-AM-AUTHORIZED`, incremental phases, auto-spawned listener/C2 terminals).

## 1. Declare scope (required)

Create `scope-authorized.txt` in the repo root (gitignored). One entry per line — exact hostnames or CIDR you are authorized to test:

```text
# Written RoE dated 2026-10-27, ticket SEC-1234
staging-php.customer-internal.example
10.20.30.0/24
```

No file → no assessment run. This is the gate.

## 2. Run the audit against your host

```bash
export PATCH_AUDIT_URL='https://staging-php.customer-internal.example/index.php'
vtbw-php2shell-lab assess run vendor-patch
vtbw-php2shell-lab assess run upload-progress-off
vtbw-php2shell-lab assess run waf-php2shell-signature
# or all non-destructive checks:
vtbw-php2shell-lab assess run all
```

Evidence lands in `out/audit/` (JSONL) plus `assess report` markdown.

## 3. Interpret

| Result | Meaning |
|--------|---------|
| `vendor-patch` PASS | PHP ≥ vendor fix for CVE-2026-109618/619 — primary fix done |
| `upload-progress-off` PASS | `session.upload_progress.enabled=0` effective — interim CVE-2026-115560 control holds |
| `waf-*` PASS | Your WAF/edge rule blocks the probe; check the bypass scenarios for gaps |
| Any FAIL | The attack path is still open — details in the JSONL entry |

## 4. Multi-terminal convenience (lab only)

For the **isolated lab** workflow (stack up, logs, monitor, audit in parallel), a tmux helper spawns the panes:

```bash
vtbw-php2shell-lab session lab        # tmux: target up | logs | audit | monitor
```

The session helper is scoped to lab commands. It is not an attack executor and takes no target argument.

## Rules of engagement

Written authorization before testing anything not yours. `scope-authorized.txt` is your machine-checkable copy of that authorization. See [SECURITY.md](../SECURITY.md).
