#!/usr/bin/env python3
"""
MCP server: PHP2Shell — unchained lab (By Leviticus-Triage).
Stdio MCP — steuert vtbw-php2shell-lab / lab-dispatch (nur autorisiertes Lab).
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

from mcp.server.fastmcp import FastMCP

LAB = Path(os.environ.get("PHP2SHELL_LAB_ROOT", "")).resolve()
if not LAB.is_dir():
    LAB = Path(__file__).resolve().parents[1]

WRAPPER = Path(
    os.environ.get(
        "VTBW_LAB_WRAPPER",
        str(LAB / "bin" / "vtbw-php2shell-lab"),
    )
).resolve()

ALLOWED_COMMANDS = frozenset(
    """
    up test monitor doctor rce shell jackalsyn apache-up apache-multi-up
    fetch-zer061 fetch-jackalsyn fetch-singularity fetch-sliver fetch-reverse-shell
    zer061 zer061-shell scan fingerprint exploit-list exploit-multi
    docs tools reverse-shell revshell export menu unchained help ps logs down
    patch-audit mitigation-audit external tor workarounds wa
    validate validation validation-matrix
    workflow-verify verify-workflow
    """.split()
)

WORKAROUNDS_SUB = frozenset({"guide", "help", "list", "run", "auto", "last", "logs"})

SLIVER_SUB = frozenset(
    {
        "status", "help", "server-up", "operator", "listener", "http-listener",
        "implant", "implant-external", "stage", "ops", "console", "down",
    }
)

TUNNEL_SUB = frozenset({"status", "up", "url", "down"})

TOR_SUB = frozenset({"status", "help", "up", "ip", "log", "down"})

EXTERNAL_SUB = frozenset({"help", "up", "status", "url", "env", "patch-audit", "down"})

JACKALSYN_SUB = frozenset({"selftest", "syms", "lab", "status", "help", "paths"})

SINGULARITY_SUB = frozenset(
    {
        "status",
        "help",
        "paths",
        "fetch",
        "runtime",
        "detect",
        "container-up",
        "container-build",
        "container-shell",
        "host-check",
        "host-build",
        "vm-wizard",
        "vm-up",
    }
)

mcp = FastMCP(
    "php2shell-unchained",
    instructions=(
        "PHP2Shell unchained. Menü: [1] FPM, [2] Zer061 oder [3] Jackalsyn, [4] Multi, "
        "[5] lukechilds-rs (Kit-Shell ist zer061-shell), [6] Sliver C2 + External "
        "(external up [--tor] = Tunnel web+sliver-http, Ursprungs-Verschleierung via Tor), "
        "[7] Singularity, [8] workarounds (Schritt-fuer-Schritt, Log+Auswertung, nur Terminal 1) "
        "+ patch-audit, [9] docs, [d] docker. "
        "logs: target|apache|singularity|sliver|tunnel|tunnel-sliver|tor. "
        "Nutze lab_help und lab_run. Keine Produktions-URLs. "
        f"Lab: {LAB}. Wrapper: {WRAPPER}."
    ),
)


def _run_wrapper(argv: list[str], timeout: int = 600, extra_env: dict[str, str] | None = None) -> str:
    if not WRAPPER.is_file():
        return f"FEHLER: Wrapper fehlt: {WRAPPER}"
    env = os.environ.copy()
    env["VTBW_LAB_WRAPPER"] = str(WRAPPER)
    if extra_env:
        env.update(extra_env)
    try:
        p = subprocess.run(
            [str(WRAPPER), *argv],
            cwd=str(LAB),
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
    except subprocess.TimeoutExpired:
        return f"TIMEOUT nach {timeout}s: {' '.join(argv)}"
    out = (p.stdout or "") + (p.stderr or "")
    if not out.strip():
        out = f"(exit {p.returncode}, keine Ausgabe)"
    return out[:120_000]


@mcp.tool()
def lab_help() -> str:
    """Vollständige CLI-/Menü-Übersicht des Labs."""
    return _run_wrapper(["help"], timeout=30)


@mcp.tool()
def lab_status() -> str:
    """Docker-Container-Status (vtbw-php2shell-*)."""
    return _run_wrapper(["ps"], timeout=30)


@mcp.tool()
def lab_run(command: str, subcommand: str = "", extra: str = "") -> str:
    """
    Führt einen Lab-Befehl aus (Whitelist).

    command: z.B. up, test, zer061, jackalsyn, scan, shell, apache-up, fetch-zer061
    subcommand: jackalsyn/singularity/patch-audit/logs (target|apache|singularity)
    extra: patch-audit run = Szenario (z.B. vendor-patch); tunnel = mode (web|sliver-http)
    """
    cmd = command.strip().lower()
    sub = subcommand.strip().lower()
    extra_arg = extra.strip()
    if cmd == "jackalsyn" or cmd in JACKALSYN_SUB:
        if cmd in JACKALSYN_SUB and not sub:
            return _run_wrapper(["jackalsyn", cmd], timeout=600)
        if cmd == "jackalsyn":
            return _run_wrapper(["jackalsyn", sub or "status"], timeout=600)
        return _run_wrapper(["jackalsyn", cmd], timeout=600)
    if cmd in ("workarounds", "wa") or cmd in WORKAROUNDS_SUB:
        # subcommand: run|auto|last|logs|guide ; extra: einzelne Schritt-ID (optional)
        sub_eff = sub if (cmd in ("workarounds", "wa") and sub) else (cmd if cmd in WORKAROUNDS_SUB else "guide")
        argv = ["workarounds", sub_eff]
        if extra_arg:
            argv.append(extra_arg)
        return _run_wrapper(argv, timeout=900)
    if cmd in ("patch-audit", "mitigation-audit"):
        if not sub or sub == "help":
            return _run_wrapper(["patch-audit", "help"], timeout=60)
        if sub == "list":
            return _run_wrapper(["patch-audit", "list"], timeout=120)
        if sub in ("run", "all"):
            scenario = extra_arg or "all"
        else:
            scenario = sub
        audit_env = {}
        if scenario == "upload-progress-off":
            audit_env["PATCH_AUDIT_DESTRUCTIVE"] = "1"
        return _run_wrapper(["patch-audit", "run", scenario], timeout=900, extra_env=audit_env)
    if cmd == "sliver" or cmd in SLIVER_SUB:
        if cmd in SLIVER_SUB and not sub:
            return _run_wrapper(["sliver", cmd], timeout=900)
        if cmd == "sliver":
            return _run_wrapper(["sliver", sub or "status"], timeout=900)
        return _run_wrapper(["sliver", cmd], timeout=900)
    if cmd == "tunnel" or cmd in TUNNEL_SUB:
        if cmd in TUNNEL_SUB and not sub:
            return _run_wrapper(["tunnel", cmd], timeout=300)
        if cmd == "tunnel":
            return _run_wrapper(["tunnel", sub or "status", extra_arg] if extra_arg else ["tunnel", sub or "status"], timeout=300)
        return _run_wrapper(["tunnel", cmd, extra_arg] if extra_arg else ["tunnel", cmd], timeout=300)
    if cmd == "tor" or cmd in TOR_SUB:
        if cmd in TOR_SUB and not sub:
            return _run_wrapper(["tor", cmd], timeout=600)
        if cmd == "tor":
            return _run_wrapper(["tor", sub or "status", extra_arg] if extra_arg else ["tor", sub or "status"], timeout=600)
        return _run_wrapper(["tor", cmd], timeout=600)
    if cmd == "external" or cmd in EXTERNAL_SUB:
        # extra: "--tor" bei up/down, Szenario bei patch-audit, mode bei url
        if cmd in EXTERNAL_SUB and not sub:
            return _run_wrapper(["external", cmd, extra_arg] if extra_arg else ["external", cmd], timeout=900)
        if cmd == "external":
            return _run_wrapper(["external", sub or "status", extra_arg] if extra_arg else ["external", sub or "status"], timeout=900)
        return _run_wrapper(["external", cmd, extra_arg] if extra_arg else ["external", cmd], timeout=900)
    if cmd == "singularity" or cmd in SINGULARITY_SUB:
        if cmd in SINGULARITY_SUB and not sub:
            return _run_wrapper(["singularity", cmd], timeout=900)
        if cmd == "singularity":
            return _run_wrapper(["singularity", sub or "status"], timeout=900)
        return _run_wrapper(["singularity", cmd], timeout=900)
    if cmd == "reverse-shell" or cmd == "revshell":
        return _run_wrapper(["reverse-shell", sub or "help"], timeout=600)
    if cmd == "docs":
        return _run_wrapper(["docs", sub or "list"], timeout=60)
    if cmd == "tools":
        return _run_wrapper(["tools", sub or "list"], timeout=300)
    if cmd not in ALLOWED_COMMANDS:
        return (
            f"Unbekannter Befehl: {command!r}. Erlaubt: {sorted(ALLOWED_COMMANDS)} "
            f"+ jackalsyn/singularity/reverse-shell Subcommands."
        )
    argv = [cmd]
    if sub and cmd not in ("jackalsyn", "singularity", "sliver", "tunnel", "patch-audit", "mitigation-audit", "reverse-shell", "docs", "tools"):
        argv.append(sub)
    timeout = 900 if cmd in ("zer061", "zer061-shell", "exploit-list", "scan", "monitor") else 600
    return _run_wrapper(argv, timeout=timeout)


@mcp.tool()
def lab_read_doc(doc: str = "HOWTO-DE") -> str:
    """
    Liest Lab-Dokumentation (Auszug).

    doc: HOWTO-DE | EXPLOIT-CHAIN | README | PORTABLE | CURSOR | SINGULARITY | PATCH-AUDIT
    """
    mapping = {
        "HOWTO-DE": LAB / "docs" / "HOWTO-DE.md",
        "EXPLOIT-CHAIN": LAB / "docs" / "EXPLOIT-CHAIN-COMPARISON.md",
        "README": LAB / "README.md",
        "PORTABLE": LAB / "README-PORTABLE.md",
        "CURSOR": LAB / "docs" / "CURSOR-INTEGRATION.md",
        "SINGULARITY": LAB / "docs" / "SINGULARITY-LAB.md",
        "PATCH-AUDIT": LAB / "docs" / "PATCH-BYPASS-AUDIT.md",
        "WORKAROUNDS": LAB / "docs" / "WORKAROUNDS-SCHRITT-FUER-SCHRITT.md",
        "WORKFLOW-KOMPLETT": LAB / "docs" / "WORKFLOW-KOMPLETT.md",
        "WORKFLOW": LAB / "docs" / "WORKFLOW-KOMPLETT.md",
    }
    path = mapping.get(doc.upper().replace(".MD", ""), mapping["HOWTO-DE"])
    if doc.endswith(".md"):
        path = LAB / "docs" / doc
    if not path.is_file():
        return f"Nicht gefunden: {path}"
    text = path.read_text(encoding="utf-8", errors="replace")
    return text[:80_000]


@mcp.tool()
def lab_exploit_map() -> str:
    """Kurzübersicht: welcher Exploit-Pfad wofür (FPM / Zer061 / Jackalsyn)."""
    return _run_wrapper(["help"], timeout=15) + "\n\n" + (
        "=== Agent-Kurzmap ===\n"
        "1) shell/rce = Chain A (FPM+LFI) — zuverlässiges www-data\n"
        "2) zer061/zer061-shell = mod_php Heap (Apache 19288)\n"
        "3) jackalsyn lab = FCGI Forschung (target:9000), oft kein RCE\n"
        "4) test/doctor = UAF PoC nur, kein Shell-RCE\n"
        "5) sliver = C2 Post-Exploit (Menü [6]) + tunnel (externe Sicht)\n"
        "6) singularity = optional Post-Exploit LKM (Menü [7], nicht in PHP-Container)\n"
        "7) workarounds run|auto = geführter Workaround-Ablauf [8] (Log: out/workarounds/); patch-audit = Einzelchecks\n"
        "8) reverse-shell = lukechilds [5]; zer061-shell = Kit-Weg [2]\n"
        "9) external up [--tor] = kompletter External-Modus [6]: Tunnel web+sliver-http,\n"
        "   Ursprung via Tor verschleiert; external patch-audit <id>; sliver implant-external\n"
        "Pfad: [1] dann [2] oder [3], danach [6]/[7]. Sec-Team [8]. logs target|apache|singularity|sliver|tunnel|tor\n"
        "Menü: php2shell-unchained | Doku: lab_read_doc HOWTO-DE\n"
    )


if __name__ == "__main__":
    mcp.run()
