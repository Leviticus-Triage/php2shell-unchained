# How to run the lab

Authorized hosts only. The compose stack is the target. Do not point the CLI at production.

## 1. Install

```bash
git clone https://github.com/Leviticus-Triage/php2shell-unchained.git
cd php2shell-unchained
./scripts/install-commands.sh
vtbw-php2shell-lab help
```

`php2shell-unchained` with no arguments opens the menu in the screenshot on the README.

## 2. Admin path (recommended first run)

One terminal. No second window.

```bash
vtbw-php2shell-lab doctor
vtbw-php2shell-lab workarounds auto
vtbw-php2shell-lab workarounds last
```

`doctor` checks Docker, images, and the lab port. `workarounds auto` records a baseline. `workarounds last` prints the markdown evaluation. Guided changes (edit ini or WAF, press enter, re-measure) use `workarounds run`.

Reports: `out/workarounds/<UTC>/` with `session.log`, `steps.jsonl`, and `auswertung.md`.

Scenario list:

```bash
vtbw-php2shell-lab patch-audit list
```

German walkthrough: [WORKAROUNDS-SCHRITT-FUER-SCHRITT.md](WORKAROUNDS-SCHRITT-FUER-SCHRITT.md).

## 3. What the menu is for

| Entry | Use it when |
|-------|-------------|
| [8] Workarounds | You need evidence that a PHP or WAF change holds |
| [1] FPM lab | You need the isolated nginx and PHP-FPM target up |
| [h] Help | You want the command index without reading the menu |
| [d] Docker | You want `ps`, logs, or `down` |
| [0] | Leave the menu |

Emulation entries ([2]–[7]) assume the stack from [1] and the same isolated network. Keep listeners and consoles on the lab host.

## 4. Stop

```bash
vtbw-php2shell-lab down
```

## 5. Read next

| Question | Document |
|----------|----------|
| Every flag and env var | [DOCUMENTATION.md](DOCUMENTATION.md) |
| Which chain the lab can exercise | [EXPLOIT-CHAIN-COMPARISON.md](EXPLOIT-CHAIN-COMPARISON.md) |
| What a control is supposed to stop | [PATCH-BYPASS-AUDIT.md](PATCH-BYPASS-AUDIT.md) |
| Rules of engagement | [../SECURITY.md](../SECURITY.md) |
