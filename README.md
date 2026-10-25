# PHP2Shell — unchained

**By Leviticus-Triage**

Isoliertes Docker-Lab für PHP2Shell (CVE-2026-109618 / CVE-2026-109619), Zer061-mod_php, Jackalsyn, Sliver-C2, Cloudflare Quick Tunnel, optionalen Tor-Egress, Singularity und Patch-Audit.

Vollständige Beschreibung des aktuellen Stands: **[docs/DOCUMENTATION.md](docs/DOCUMENTATION.md)**

## Befehle

```bash
git clone <dieses-repo> php2shell-lab-vtbw
cd php2shell-lab-vtbw
scripts/install-commands.sh
```

Danach, aus jedem Arbeitsverzeichnis (sofern `~/.local/bin` im `PATH` liegt):

```bash
vtbw-php2shell-lab help
php2shell-unchained
vtbw-php2shell-doctor
```

Ohne Installation der Symlinks:

```bash
bin/vtbw-php2shell-lab help
```

## Workarounds prüfen — Start hier (1 Terminal)

```bash
vtbw-php2shell-lab workarounds run    # geführt: ändern → ENTER → Prüfung → Auswertung
vtbw-php2shell-lab workarounds auto   # nur messen (Baseline)
vtbw-php2shell-lab workarounds last   # Auswertung der letzten Sitzung
```

Alles wird mitgeloggt nach `out/workarounds/<UTC-Zeit>/` (`session.log`, `steps.jsonl`, `auswertung.md`).
Anleitung mit Terminal-Angaben: **[docs/WORKAROUNDS-SCHRITT-FUER-SCHRITT.md](docs/WORKAROUNDS-SCHRITT-FUER-SCHRITT.md)**

`third_party/` und `out/` liegen nicht im Git. Bundles: `fetch-zer061`, `fetch-jackalsyn`, `fetch-sliver`, `fetch-singularity`, `fetch-reverse-shell`.

Phasenablauf: [docs/HOWTO-DE.md](docs/HOWTO-DE.md)

Hinweis zur zulässigen Nutzung: Ende von [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md).
