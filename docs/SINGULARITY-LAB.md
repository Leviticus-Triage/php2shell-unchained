# Singularity — Post-Exploit im Lab

**By Leviticus-Triage** — nur autorisierte Systeme (VM, Testhost, privilegierter Lab-Container).

## Einordnung

| Schritt | Menü / CLI |
|---------|------------|
| Web-RCE | [1] shell, [2] zer061-shell, [4] reverse-shell |
| **Optional Post-Exploit** | **[7] Singularity** |

Singularity (upstream [MatheuZSecurity/Singularity](https://github.com/MatheuZSecurity/Singularity)) ist ein **Kernel-LKM**. Es läuft **nicht** in den gehärteten PHP-Containern (`target`, `target-apache`).

## Phase 0

```bash
vtbw-php2shell-lab fetch-singularity
```

## Laufzeitmodi

| Modus | Befehl | Hinweis |
|-------|--------|---------|
| **container** | `singularity container-up` → `container-build` | Host-Kernel + Headers, `CONFIRM_SINGULARITY_CONTAINER=I_UNDERSTAND_REBOOT` |
| **host** | `singularity host-check` → `host-build` | `CONFIRM_SINGULARITY_HOST=I_UNDERSTAND_REBOOT`, Reboot zum Entfernen |
| **vm** | `singularity vm-wizard` | Empfohlen; siehe [singularity/vm/README.md](../singularity/vm/README.md) |

Laufzeit merken: `singularity runtime` oder `SINGULARITY_RUNTIME=vm singularity runtime`.

## Blue Team

```bash
vtbw-php2shell-lab singularity detect
SINGULARITY_DETECT_TARGET=all singularity detect
```

## Agent / MCP

`lab_run(command="singularity", subcommand="status")`  
`lab_run(command="fetch-singularity")`

## Abbruchkriterien

- Kein automatischer Aufruf nach `shell` / `zer061`.
- Build ohne `CONFIRM_*` wird abgebrochen.
- Compose-Profil `singularity` startet nicht mit normalem `up`.
