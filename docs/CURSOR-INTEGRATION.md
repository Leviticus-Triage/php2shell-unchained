# Cursor-Integration — PHP2Shell unchained

**By Leviticus-Triage**

Damit der Agent das Lab vollständig bedienen und erklären kann, gibt es drei Ebenen:

| Ebene | Zweck |
|--------|--------|
| **Skill** | `.cursor/skills/php2shell-unchained/SKILL.md` — Wann/wie der Agent handelt |
| **Rule** | `.cursor/rules/php2shell-unchained.mdc` — Kontext im Lab-Ordner |
| **MCP** | `mcp/php2shell_lab_mcp.py` — Tools: `lab_run`, `lab_help`, `lab_status`, … |

## 1. MCP aktivieren (empfohlen)

### Variante A — Projekt (automatisch, wenn Cursor Projekt-MCP lädt)

Datei liegt bereits unter:

`php2shell-lab-vtbw/.cursor/mcp.json`

Workspace in Cursor öffnen: **Ordner `php2shell-lab-vtbw` oder `cursor-projects`**.

### Variante B — Global (alle Projekte)

```bash
~/Schreibtisch/cursor-projects/php2shell-lab-vtbw/scripts/install-cursor-mcp.sh
```

Fügt den Server `php2shell-unchained` in `~/.cursor/mcp.json` ein (ohne andere Server zu löschen).

Danach: **Cursor → Settings → MCP** → Server `php2shell-unchained` grün / neu laden.

## 2. MCP-Tools

| Tool | Funktion |
|------|----------|
| `lab_help` | Alle CLI-Befehle |
| `lab_status` | `docker ps` Lab-Container |
| `lab_run` | Whitelist. Argumente: `command`, `subcommand`, `extra` |
| `lab_read_doc` | `HOWTO-DE`, `WORKFLOW-KOMPLETT`, `WORKFLOW`, `EXPLOIT-CHAIN`, `CURSOR`, `SINGULARITY`, `PATCH-AUDIT`, `WORKAROUNDS` |
| `lab_exploit_map` | FPM, Zer061, Jackalsyn, Singularity, Patch-Audit |

Menüpfad für den Agenten: **[1]** FPM → **[2]** oder **[3]** → **[6]** Singularity. Sec-Team **[7]**. **[5]** ist lukechilds, Kit-Shell ist `zer061-shell`.

Beispiele:

- `lab_run(command="zer061")`
- `lab_run(command="jackalsyn", subcommand="selftest")`
- `lab_run(command="logs", subcommand="apache")`
- `lab_run(command="patch-audit", subcommand="run", extra="waf-bypass-top10")`
- `lab_run(command="sliver", subcommand="listener")`
- `lab_run(command="tunnel", subcommand="up", extra="web")`
- `lab_run(command="external", subcommand="up", extra="--tor")` — kompletter External-Modus (Tunnel web+sliver-http via Tor)
- `lab_run(command="external", subcommand="patch-audit", extra="waf-bypass-top10")`
- `lab_run(command="tor", subcommand="ip")` — Host-IP vs. Tor-Exit (Verschleierungs-Beweis)
- `lab_run(command="sliver", subcommand="implant-external")` — HTTPS-C2-Implant gegen Tunnel-Host
- `lab_run(command="singularity", subcommand="status")`

## 3. Menü & CLI (User)

```bash
~/Schreibtisch/cursor-projects/php2shell-unchained
~/Schreibtisch/cursor-projects/vtbw-php2shell-lab help
```

## 4. Skill für andere Workspaces

Skill liegt im Repo unter `.cursor/skills/`. Optional nach global kopieren:

```bash
mkdir -p ~/.cursor/skills/php2shell-unchained
cp -r php2shell-lab-vtbw/.cursor/skills/php2shell-unchained/* ~/.cursor/skills/php2shell-unchained/
```

## 5. Kein separates „Marketplace-Plugin“

Es gibt **kein** externes Cursor-Marketplace-Plugin — die offizielle Integration ist **Projekt-Skill + Rule + MCP** (wie Playwright/Notion über `mcp.json`).

## 6. Portable Export

Nach `vtbw-php2shell-lab export` sind `.cursor/` und `mcp/` im Lab-Ordner enthalten; Pfade in `mcp.json` ggf. anpassen (`install-cursor-mcp.sh`).
