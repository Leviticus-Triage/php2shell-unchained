#!/usr/bin/env bash
LAB="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER="${VTBW_LAB_WRAPPER:-$LAB/bin/vtbw-php2shell-lab}"
cat <<EOF
PHP2Shell - unchained | By Leviticus-Triage

  START HIER — Workarounds prüfen (1 Terminal, mit Log + Auswertung):
    $WRAPPER workarounds run     Schritt für Schritt: ändern → ENTER → Prüfung
    $WRAPPER workarounds auto    Nur messen (Baseline, ohne Rückfragen)
    $WRAPPER workarounds last    Auswertung der letzten Sitzung
    Doku: docs/WORKAROUNDS-SCHRITT-FUER-SCHRITT.md

  $WRAPPER menu              Interaktives ASCII-Menü
  Pfad: [1] FPM → [2] Zer061 oder [3] Jackalsyn → [6] Sliver C2 / [7] Singularity. Sec-Team [8].
  Terminals: Workaround-Ablauf = nur Terminal 1. Terminal 2 nur bei shell,
    sliver console, reverse-shell listen und logs <ziel> (blockieren das Fenster).
  logs target|apache|singularity|sliver|tunnel|tunnel-sliver|tor

FPM / VTBW-Target (nginx + PHP-FPM)
  up | test | doctor | rce | shell | monitor | logs | ps | down

Zer061 mod_php (Heap RCE)
  apache-up | apache-multi-up    1 bzw. 2 Apache-Targets im Lab-Netz
  fetch-zer061 | zer061 | zer061-shell

Scan / Multi-Target (Kit: scanner.py + exploit.py -l)
  scan [targets.txt]           Mass-Scan (--deep optional: DEEP=1)
  fingerprint [file]           Nur Fingerprint (--scan-only)
  exploit-list [file]          Auto-Exploit Liste (-t THREADS)

Reverse Shell (lukechilds/reverse-shell + Kit)
  fetch-reverse-shell          Clone Payload-Generator nach third_party/
  reverse-shell fetch|listen|zer061   Payload out/r, Listener, Heap-Trigger

Jackalsyn
  fetch-jackalsyn | jackalsyn selftest|syms|lab

Sliver C2 (Post-Exploit Adversary Emulation, BishopFox)
  fetch-sliver | sliver server-up|operator|listener|http-listener|implant|implant-external|console
  sliver http-listener + tunnel up sliver-http → externe C2-Sicht

External-Attacker (Tunnel web+sliver-http, optional Tor-Egress)
  external up [--tor] | external status | external env | external patch-audit <id>
  external down [--tor]   tor up|ip|status|down

Cloudflare Quick Tunnel (externe Angreifer-Perspektive, kein Account)
  tunnel up web|sliver-http [--tor] | tunnel url | tunnel status | tunnel down

Workarounds + Patch-Audit (Sec-Teams, nur eigene Ziele)
  workarounds | workarounds run|auto|last|logs   Geführt, Log: out/workarounds/
  patch-audit list | patch-audit run <id>|all | patch-audit logs
  PATCH_AUDIT_URL=… PATCH_AUDIT_DESTRUCTIVE=1 …

Singularity (Post-Exploit LKM — VM/Host/Container, nicht in PHP-Targets)
  fetch-singularity | singularity status|runtime|detect
  singularity container-up|container-build | host-check|host-build | vm-wizard

Kit internals
  docs [list|open NAME]        Zer061 Analyse-Markdown
  tools [list|run SCRIPT]      tools/*.py Forschungs-Skripte

  validate                   Full-Stack-Matrix (FPM-Versionen, Zer061, External, Auswertung)
  workflow-verify            Stichprobe Setup→Exploit→Post-Exploit (Log: out/workflow-verify/)
  export                     Portable tar.gz

Lab: $LAB
EOF
