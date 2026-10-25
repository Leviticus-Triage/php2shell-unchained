# Workarounds — Schritt für Schritt

**Ein Befehl, ein Terminal, ein Log.** Diese Anleitung führt in fester Reihenfolge durch alle Workarounds, die das Tool prüfen kann. Du wendest jede Änderung selbst an, das Tool prüft danach und schreibt alles mit.

## Start (genau so)

```bash
# Terminal 1 — von jedem Ordner aus:
vtbw-php2shell-lab workarounds run
```

Das war es. Der Runner zeigt pro Schritt: was zu ändern ist, wo, dann wartet er auf dein ENTER, prüft, loggt und macht am Ende eine Auswertung.

Nur messen, ohne Rückfragen (Baseline):

```bash
vtbw-php2shell-lab workarounds auto
```

Einzelnen Schritt wiederholen (nach dem Nachjustieren):

```bash
vtbw-php2shell-lab workarounds run waf-bypass-top10
```

## Wie viele Terminals?

| Situation | Terminals | Erklärung |
|---|---|---|
| **Dieser Workaround-Ablauf** | **1** | Alles — Änderung lesen, ENTER, Prüfung, Auswertung — läuft in Terminal 1. Ein zweites Terminal ist bei keinem Schritt Pflicht. |
| Optional: Live-Logs ansehen | 2 | Nur Beobachtung, z. B. WAF-Log oder `vtbw-php2shell-lab logs target`. Der Ablauf wartet nicht darauf. Steht bei jedem Schritt dabei. |
| `shell` (interaktive Lab-Shell) | 2 | Terminal 1 ist durch die Shell belegt. Für weitere Befehle Terminal 2 öffnen. |
| `sliver console` | 2 | Wie Shell: Konsole belegt Terminal 1. |
| `reverse-shell listen` | 2 | Listener blockiert Terminal 1, Auslöser läuft in Terminal 2. |
| `logs <ziel>` (target/apache/sliver/tunnel/tor) | 2 | `docker logs -f` folgt dem Log und blockiert das Fenster. |
| `external up`, `tor up`, `tunnel up` | 1 | Starten Container im Hintergrund, blockieren nichts. |

Faustregel: Blockiert ein Befehl das Fenster (Shell, Konsole, Listener, `logs -f`), brauchst du für alles Weitere ein zweites Terminal. Der Workaround-Runner blockiert nicht.

## Ziel wählen

Standard ist das Lab (`http://target/index.php`, Apache `http://target-apache/index.php`).

Eigenes Staging-/Testsystem (nur mit Freigabe):

```bash
PATCH_AUDIT_URL=https://staging.example/index.php \
PATCH_AUDIT_APACHE_URL=https://staging.example/index.php \
  vtbw-php2shell-lab workarounds run
```

Über Cloudflare-Tunnel + Tor (External-Modus, Menü [6]):

```bash
vtbw-php2shell-lab external up --tor
eval "$(vtbw-php2shell-lab external env)"
vtbw-php2shell-lab workarounds run
```

## Was wird mitgeloggt?

Jede Sitzung legt einen eigenen Ordner an: `out/workarounds/<UTC-Zeit>/`

| Datei | Inhalt |
|---|---|
| `session.log` | Alles, was während der Sitzung auf dem Bildschirm stand (Bildschirm = Log). |
| `steps.jsonl` | Ein JSON-Datensatz pro Schritt: Zeit (UTC), Schritt-ID, Audit-Status, Detail. |
| `step-NN-<id>.log` | Rohausgabe der Prüfung dieses Schritts. |
| `auswertung.md` | Abschlusstabelle: OK / OFFEN / PRÜFEN / NUR INFO / NICHT GEPRÜFT + Nachjustieren pro offenem Schritt. |
| `out/audit/patch-audit.jsonl` | Zusätzlich die HTTP-Einzelproben des Audits (inkl. `proxy`-Feld). |

Ansehen:

```bash
vtbw-php2shell-lab workarounds last    # Auswertung der letzten Sitzung
vtbw-php2shell-lab workarounds logs    # alle Sitzungen
```

Auswertung lesen: **OFFEN** = Audit noch FAIL, Änderung greift (noch) nicht. Die Spalte „Nachjustieren" sagt, was zu ändern ist. Danach nur diesen Schritt erneut: `workarounds run <id>`. **NUR INFO** = der Check ist ein Config-Hinweis und kann allein nichts nachweisen (Schritte 3–5). Im `auto`-Modus heißt OFFEN nur: Ausgangszustand gemessen, es wurde vorher nichts geändert.

## Die Schritte

Reihenfolge des Runners. In Klammern die Audit-ID für Einzelprüfungen (`patch-audit run <id>`).

### Schritt 1 — Vendor-Patch (`vendor-patch`) · Terminal 1

Änderung: PHP auf das Fix-Release deines Zweigs: 8.5 → 8.5.12+, 8.4 → 8.4.27+, 8.3 → 8.3.36+, 8.2 → 8.2.35+. Für 8.1 führt das Audit keinen Fix. FPM und mod_php getrennt. Danach Dienst neu starten, ENTER.
Prüfung: Version aus `X-Powered-By`/Body gegen die Fix-Tabelle. PASS = Version ≥ Fix.

### Schritt 2 — Upload-Progress aus (`upload-progress-off`) · Terminal 1

Änderung (FPM-Pool `www.conf`):

```ini
php_admin_flag[session.upload_progress.enabled] = off
```

Apache/global: `session.upload_progress.enabled = Off` in der php.ini. Nicht per `ini_set()` und nicht per `.user.ini`. FPM/Apache neu starten, ENTER.
Prüfung: 1 UAF-Runde gegen das Ziel (`PATCH_AUDIT_DESTRUCTIVE=1` setzt der Runner selbst). PASS = UAF arm't nicht.

### Schritt 3 — Stelle der Einstellung (`ini-set-late`) · Terminal 1

Änderung: In FPM-Pool und php.ini prüfen, dass die Einstellung aus Schritt 2 dort steht — und nirgends per `ini_set('session.upload_progress.enabled', …)` im Code gesetzt wird. ENTER.
Prüfung: Config-Hinweis (INFO). Nachweis läuft über Schritt 2.

### Schritt 4 — memory_limit (`memory-limit-workaround`) · Terminal 1

Änderung: `memory_limit` (z. B. 256M) in php.ini/FPM-Pool, Dienst neu starten, ENTER.
Prüfung: INFO — ein erhöhtes Limit allein ist im Audit kein Fix-Nachweis für CVE-2026-109618. Nachweis läuft über Schritt 1.

### Schritt 5 — serialize_handler (`cve-115560-config`) · Terminal 1

Änderung: Im Webroot suchen und entfernen, falls zur Laufzeit umgeschaltet wird:

```bash
grep -rn "serialize_handler" <webroot>
```

Gemeint ist ein Wechsel von `php_serialize` auf `php` bei aktivem Upload-Progress. ENTER.
Prüfung: Config-Hinweis (INFO).

### Schritt 6 — WAF-Signatur (`waf-php2shell-signature`) · Terminal 1 · optional Terminal 2 (WAF-Log)

Änderung: WAF-Regel vor dem Ziel aktivieren: POST + Cookie `PHPSESSID` + Feld `PHP_SESSION_UPLOAD_PROGRESS` → 403/406/429. Body-Inspektion muss an sein und den Request-Body abdecken. Regel veröffentlichen, ENTER.
Prüfung: 4 Schreibweisen des Feldnamens. PASS = alle geblockt.

### Schritt 7 — WAF Top-10 (`waf-bypass-top10`) · Terminal 1 · optional Terminal 2 (WAF-Log)

Änderung: Keine neue — dieselbe WAF wie Schritt 6. ENTER.
Prüfung: 10 Proben (Kleinschreibung, Mixed Case, `%50`, `%2550`, doppelter Boundary, Tab, chunked, zwei Felder, `/**/` im Namen, `multipart/related`). PASS = 0 Proben erreichen PHP, Ergebnisliste steht im Schritt-Log und in `out/audit/patch-audit.jsonl`.

### Schritt 8 — Multipart an der Edge blocken (`edge-multipart-block`) · Terminal 1 · optional Terminal 2 (CDN-Log)

Änderung: CDN/Reverse-Proxy-Regel: `multipart/form-data` → 403/405. Datei-Uploads der App laufen über diesen Pfad dann nicht mehr. Regel veröffentlichen, ENTER.
Prüfung: multipart-POST. PASS = 403/405.

### Schritt 9 — LFI schließen (`chain-a-lfi`) · Terminal 1

Änderung: Kein `include`/`require` mit Wert aus `$_GET`/`$_POST`/`$_REQUEST`. Feste Whitelist statt Dateiname aus der URL:

```bash
grep -rn "include.*_GET\|include.*_POST\|include.*_REQUEST" <webroot>
```

Code ausrollen, ENTER.
Prüfung: `?page=../../../../etc/passwd`. PASS/INFO = kein `root:` im Body.

### Schritt 10 — mod_php-Heap (`zer061-heap`) · Terminal 1

Änderung: Apache/mod_php auf PHP 8.4.27+, getrennt vom FPM-Stack. Apache neu starten, ENTER. Ziel über `PATCH_AUDIT_APACHE_URL`.
Prüfung: PHP-Version des Apache-Ziels. PASS = ≥ 8.4.27.

### Schritt 11 — Host-Erkennung (`singularity-detect`) · Terminal 1 (Host)

Änderung: Keine. ENTER startet `singularity detect` auf dem Host (Modul-Liste, `/dev/shm`, Persistenz-Hinweise; es wird kein Modul geladen).
Prüfung: Checkliste läuft durch (Status DONE). Ein leerer Befund ist bei aktivem Hide kein Abschluss — Einzelpunkte stehen im Schritt-Log.

## Danach

1. `auswertung.md` der Sitzung durchsehen: OFFEN und PRÜFEN zuerst.
2. Nachjustieren-Spalte abarbeiten, Dienst/Regel neu laden.
3. Nur den betroffenen Schritt erneut prüfen: `vtbw-php2shell-lab workarounds run <id>` — neue Sitzung, neues Log.
4. Abschluss über alles: `vtbw-php2shell-lab workarounds run` (geführt) oder `workarounds auto` (Messung).

## Disclaimer

Nur auf eigenen Systemen oder mit ausdrücklicher schriftlicher Freigabe anwenden. Der Runner ändert nichts am Ziel — jede Änderung oben trägst du selbst ein; das Tool prüft und protokolliert. Schritt 2 startet eine UAF-Probe und kann PHP-Worker belasten. Quick-Tunnel-URLs sind öffentlich erreichbar, solange der Tunnel läuft. Logs unter `out/` können Ziel-URLs und Proxy-Einstellungen enthalten und gehören nicht in öffentliche Repositories.
