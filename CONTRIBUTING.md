# Contributing

Thank you for helping improve PHP2Shell Unchained as a **defensive** lab.

## Principles

1. **Lab-only defaults** — no auto-download of weaponized bundles; `fetch-*` scripts remain explicit.
2. **Document behavior, not opinions** — technical docs describe what the tool does; mitigations are referenced from vendor advisories.
3. **Reproducibility** — new scenarios need a clear audit ID, log line in `patch_audit.py` or workarounds step, and doc cross-links.

## Development setup

```bash
git clone https://github.com/Leviticus-Triage/php2shell-unchained.git
cd php2shell-unchained
./scripts/install-commands.sh
vtbw-php2shell-doctor
```

## Pull requests

- Keep changes focused; match existing shell/Python style in `scripts/` and `attacker/`.
- Update `docs/DOCUMENTATION.md` and README tables when adding commands or audit IDs.
- Do not commit `out/`, `third_party/` payloads, or secrets.

## CI

GitHub Actions runs lightweight shell syntax checks on `scripts/` (see `.github/workflows/ci.yml`).
