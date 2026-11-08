# Security

Cadence is early software. Only the current development branch is maintained; older binaries may retain old defaults and known limitations. The custom private-device protocol has tests but has not had an independent security audit.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/bahachammakhi/cadence-music/security/advisories/new) for security-sensitive findings. Do not open a public issue with credentials, exploit details against a live server or personal network data. If the form is unavailable, do not disclose the vulnerability publicly to request contact; use an already established private channel to reach the maintainer. No response-time or bounty commitment is made.

A useful report includes the affected version, prerequisites, minimal reproduction with synthetic credentials, impact and proposed mitigation. Use a server/account you control; avoid disrupting other users.

## Scope and precautions

- Use trusted HTTPS servers. Cadence does not provide a server or promise source/provider safety.
- Keep Tailscale ACLs narrow. Mac control is private-network software, not an internet-exposed API; do not port-forward it or add a public proxy/funnel.
- Use a strong, unique Aurral password. Control keys derive from account credentials; anyone sharing that account on the permitted network is within the same control trust boundary.
- Restrict private Apple signing/API configuration outside the repository. Do not upload signing keys, cookies, raw live fixtures or unreviewed diagnostic bundles.
- If a credential is exposed, revoke/rotate it at its provider and invalidate affected sessions. Removing the current file alone does not erase Git history, caches, clones or binary releases.

See [privacy/data flow](docs/PRIVACY.md), [Mac transport](docs/MAC-CONTROL.md) and [publication checklist](docs/OPEN-SOURCE-READINESS.md). Private reporting availability is a GitHub setting, not something this file enables.
