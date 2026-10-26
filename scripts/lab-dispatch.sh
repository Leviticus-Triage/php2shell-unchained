#!/usr/bin/env bash
# Central command dispatch — source from wrapper: LAB=...; . lab-dispatch.sh; lab_dispatch "$@"
lab_dispatch() {
  local cmd_lc
  cmd_lc="$(printf '%s' "${1:-menu}" | tr '[:upper:]' '[:lower:]')"
  shift || true
  local LAB="${LAB:?}"

  case "$cmd_lc" in
    up)       exec "$LAB/scripts/lab-up.sh" ;;
    test)     exec "$LAB/scripts/lab-test.sh" ;;
    monitor)  exec "$LAB/scripts/lab-monitored-run.sh" ;;
    doctor)   exec "$LAB/scripts/lab-doctor.sh" ;;
    rce)      exec "$LAB/scripts/lab-rce.sh" test ;;
    shell)    exec "$LAB/scripts/lab-rce.sh" shell ;;
    jackalsyn) exec "$LAB/scripts/lab-jackalsyn.sh" "${1:-status}" ;;
    apache-up) exec "$LAB/scripts/lab-apache-up.sh" ;;
    apache-multi-up) exec "$LAB/scripts/lab-apache-multi-up.sh" ;;
    fetch-zer061) exec "$LAB/scripts/fetch-zer061.sh" ;;
    fetch-jackalsyn) exec "$LAB/scripts/fetch-jackalsyn.sh" ;;
    fetch-singularity) exec "$LAB/scripts/fetch-singularity.sh" ;;
    fetch-sliver) exec "$LAB/scripts/fetch-sliver.sh" ;;
    sliver)   exec "$LAB/scripts/lab-sliver.sh" "${1:-status}" "${@:2}" ;;
    tunnel)   exec "$LAB/scripts/lab-tunnel.sh" "${1:-status}" "${@:2}" ;;
    tor)      exec "$LAB/scripts/lab-tor.sh" "${1:-status}" "${@:2}" ;;
    external) exec "$LAB/scripts/lab-external.sh" "${1:-help}" "${@:2}" ;;
    fetch-reverse-shell) exec "$LAB/scripts/fetch-reverse-shell.sh" ;;
    singularity) exec "$LAB/scripts/lab-singularity.sh" "${1:-status}" ;;
    patch-audit|mitigation-audit|audit-patch)
      exec "$LAB/scripts/lab-patch-audit.sh" "${1:-help}" "${@:2}" ;;
    workarounds|wa|workaround-guide)
      exec "$LAB/scripts/lab-workarounds.sh" "${1:-guide}" "${@:2}" ;;
    zer061)   exec "$LAB/scripts/lab-zer061.sh" ;;
    zer061-shell|zer061shell|revshell-apache)
      exec "$LAB/scripts/lab-zer061-shell.sh" ;;
    scan)     exec "$LAB/scripts/lab-zer061-scan.sh" "$@" ;;
    exploit-list|exploit-multi)
      exec "$LAB/scripts/lab-zer061-exploit-list.sh" "$@" ;;
    fingerprint|scan-only)
      exec "$LAB/scripts/lab-zer061-exploit-list.sh" --scan-only "$@" ;;
    docs)     exec "$LAB/scripts/lab-zer061-docs.sh" "$@" ;;
    tools)    exec "$LAB/scripts/lab-zer061-tools.sh" "$@" ;;
    reverse-shell|revshell)
      exec "$LAB/scripts/lab-reverse-shell.sh" "$@" ;;
    export|archive)
      exec "$LAB/scripts/make-export-archive.sh" ;;
    validate|validation|validation-matrix)
      exec "$LAB/scripts/lab-validation-matrix.sh" ;;
    workflow-verify|verify-workflow)
      exec "$LAB/scripts/lab-workflow-verify.sh" ;;
    menu|unchained)
      exec "$LAB/scripts/php2shell-unchained-menu.sh" ;;
    down)
      docker rm -f vtbw-php2shell-tunnel vtbw-php2shell-tunnel-sliver vtbw-php2shell-stage vtbw-php2shell-tor 2>/dev/null || true
      rm -f "$LAB/out/external/state.env" 2>/dev/null || true
      cd "$LAB" && docker compose --profile apache --profile multi --profile singularity --profile sliver --profile tools down 2>/dev/null || true
      cd "$LAB" && docker compose down
      ;;
    ps)       docker ps --filter name=vtbw-php2shell ;;
    logs)
      case "${1:-target}" in
        target) docker logs -f vtbw-php2shell-target ;;
        apache) docker logs -f vtbw-php2shell-apache ;;
        singularity) docker logs -f vtbw-php2shell-singularity-lab ;;
        sliver) docker logs -f vtbw-php2shell-sliver ;;
        tunnel) docker logs -f vtbw-php2shell-tunnel ;;
        tunnel-sliver) docker logs -f vtbw-php2shell-tunnel-sliver ;;
        tor) docker logs -f vtbw-php2shell-tor ;;
        *)
          echo "logs target|apache|singularity|sliver|tunnel|tunnel-sliver|tor" >&2
          return 2
          ;;
      esac
      ;;
    help|-h|--help)
      exec "$LAB/scripts/lab-help.sh" ;;
    *)
      echo "Unbekannter Befehl: $cmd_lc  —  menu oder help" >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  LAB="$(cd "$(dirname "$0")/.." && pwd)"
  lab_dispatch "$@"
fi
