# Patch- & Mitigations-Audit (Bypass-Tests)

**By Leviticus-Triage** — nur auf **eigener** Infrastruktur oder im isolierten Lab.

Sec-Teams prüfen, ob Emergency-Patches und Workarounds **wirklich** greifen oder ob bekannte **Bypass-/Restrisiko-Pfade** (Stand Recherche Okt 2026) noch offen sind.

## Quellen (öffentlich)

| Quelle | Inhalt |
|--------|--------|
| [PHP News 2026](https://www.php.net/archive/2026.php) | CVE-2026-115560, `session.upload_progress.enabled=0` |
| [AWS WAF PHP2Shell](https://aws.amazon.com/blogs/security/using-aws-waf-to-apply-mitigations-for-php2shell-rce-vulnerabilities-cve-2026-109618-and-cve-2026-109619/) | WAF-Regeln, `memory_limit`, `pm.max_requests`, 115560 |
| [Google Cloud](https://cloud.google.com/blog/products/identity-security/responding-to-core-php-vulnerabilities-cve-2026-109618-cve-2026-109619) | Patched: 8.5.12, 8.4.27, 8.3.36, 8.2.35 |
| [Datadog Security Labs](https://securitylabs.datadoghq.com/articles/php2shell-critical-vulnerabilities-in-php/) | „Only patching fixes“; `upload_progress=0` nicht vollständig für beide CVEs |
| [RemiPelloux REMEDIATION](https://github.com/RemiPelloux/php-session-upload-progress-uaf/blob/main/REMEDIATION.md) | Exposure-Check, ini_admin vs `.user.ini` |

## Szenarien im Tool

| ID | Mitigation (typisch) | Was der Audit prüft |
|----|----------------------|---------------------|
| `vendor-patch` | PHP ≥ Fix-Release | Version vs. 8.4.27 / 8.3.36 / … |
| `upload-progress-off` | `session.upload_progress.enabled=Off` | 619-Pfad: PoC-UAF weiter erreichbar? (Lab) |
| `waf-php2shell-signature` | WAF: POST + Session + `PHP_SESSION_UPLOAD_PROGRESS` | Varianten-Requests (Case/Whitespace) |
| `memory-limit-workaround` | Hohes `memory_limit` | 618: OOM-Pfad theoretisch noch möglich (Hinweis) |
| `ini-set-late` | `ini_set` in App | Konfiguration zu spät — reines Config-Audit |
| `edge-multipart-block` | CDN blockiert `multipart/form-data` | Funktionale Kollision (Uploads tot) |
| `chain-a-lfi` | LFI geschlossen | Chain A (`page=`) noch nutzbar? |
| `zer061-heap` | PHP 8.4.27+ mod_php | Zer061-Kit gegen Ziel (nur Lab-Apache) |
| `cve-115560-config` | Nur upload_progress off | Serialize-Handler-Wechsel (manuell/Hinweis) |
| `singularity-detect` | LKRG/eBPF/chkrootkit | IOC-Check (Host) |
| `waf-bypass-top10` | Managed WAF-Regeln (Cloudflare/AWS/Akamai/Imperva/F5/CRS/Azure/…) | 10 Evasions: Case, Encoding, Boundary-Parser-Diff, Chunked, HPP, Kommentar, Content-Type-Mutation |

### WAF Top-10 Probes

`patch-audit run waf-bypass-top10` sendet den PHP2Shell-Marker (`PHP_SESSION_UPLOAD_PROGRESS` + `PHPSESSID`) mit zehn Evasionstechniken und wertet aus: **BLOCKED** (403/406/429) vs. **BYPASSED** (erreicht PHP). Jede Probe wird als JSONL nach `out/audit/patch-audit.jsonl` geschrieben (`patch-audit logs`).

| # | Technik | Ziel-WAF-Schwäche |
|---|---------|-------------------|
| 01 | Lowercase-Feldname | case-sensitive Rules |
| 02 | Mixed Case | schwache Normalisierung |
| 03 | URL-Encoded im multipart name | fehlendes Decoding |
| 04 | Double Encoding | doppeltes Decoding |
| 05 | Doppelter Boundary-Parameter | Parser-Differenz WAF vs. PHP |
| 06 | Tab/Whitespace in Content-Disposition | strict-RFC vs. lax Parser |
| 07 | Transfer-Encoding: chunked | fehlendes Reassembly |
| 08 | Parameter Pollution (2 Felder) | nur-erstes-Feld-Inspektion |
| 09 | Inline-Kommentar-Mutation | Pattern-Match vs. Tokenizer |
| 10 | multipart/related statt form-data | Content-Type-Whitelist |

**Hinweis:** Vollständiger Fix = **Vendor-Patch**. Workarounds reduzieren Risiko; einige Kombinationen (618 ohne Progress-Feld, 115560) umgehen einzelne Controls.

## CLI

```bash
vtbw-php2shell-lab patch-audit list
vtbw-php2shell-lab patch-audit run vendor-patch
PATCH_AUDIT_URL=http://127.0.0.1:19281/ vtbw-php2shell-lab patch-audit run all
PATCH_AUDIT_DESTRUCTIVE=1 patch-audit run upload-progress-off   # UAF-Probe
patch-audit logs 50                                             # JSONL-Trail
```

Extern (Cloudflare Quick Tunnel):

```bash
tunnel up web
PATCH_AUDIT_URL=$(tunnel url web)/index.php patch-audit run waf-bypass-top10
```

Extern + verschleierter Ursprung (Tor-Egress; `PATCH_AUDIT_PROXY` wird ins JSONL geloggt):

```bash
external up --tor
external patch-audit waf-bypass-top10
# manuell: PATCH_AUDIT_PROXY=socks5h://vtbw-php2shell-tor:9050
```

Menü **[8] Patch-Audit** bzw. **[6] → „Patch-Audit extern (Tunnel+Tor)“**.

## Lab-Erwartung

| Target | Erwartung im Audit |
|--------|-------------------|
| FPM `target` (8.4.4) | Viele Checks **FAIL** (bewusst verwundbar) |
| Nach Patch-Image | `vendor-patch` **PASS**; PoC **PASS** (nicht mehr armed) |
