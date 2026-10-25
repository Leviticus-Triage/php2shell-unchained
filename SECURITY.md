# Security policy

## Authorized use

PHP2Shell Unchained is designed for:

- Local or CI-isolated Docker labs under your control
- Staging systems where you have **written authorization** to perform security testing
- Training and patch-validation exercises documented by your organization

**Do not** aim lab commands, tunnels, exploits, or audit scripts at systems you do not own or lack explicit permission to test.

## Sensitive artifacts

Runtime output under `out/` may contain:

- Session identifiers and exploit payloads
- Tunnel URLs (`trycloudflare.com`)
- Sliver operator material and implant binaries
- Tor-related routing configuration

Treat `out/` as **confidential** during engagements; do not commit it to version control (it is gitignored).

## Reporting vulnerabilities in this project

If you discover a security issue **in this lab tooling** (not in PHP itself):

1. Open a private report via GitHub Security Advisories on [Leviticus-Triage/php2shell-unchained](https://github.com/Leviticus-Triage/php2shell-unchained/security/advisories/new), **or**
2. Contact the maintainer organization through your established channel.

Please include reproduction steps confined to an isolated lab.

## Upstream PHP vulnerabilities

For PHP core issues, follow [https://www.php.net/security.php](https://www.php.net/security.php) and your distribution’s security advisory process.
