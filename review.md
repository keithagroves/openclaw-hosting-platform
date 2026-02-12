# Architecture Review (Current)

## Summary
The current architecture provides per-customer, browser-based desktops with ClawBot installed, fronted by Caddy for automatic HTTPS and subdomain routing. Provisioning is handled via scripts and a webhook service, with customer state stored in a local JSON database.

## Strengths
- Clear separation of concerns: desktop image, reverse proxy, provisioning, and webhook service.
- Per-customer isolation via per-container networks and per-customer volumes.
- Automatic HTTPS via Caddy label discovery keeps routing simple.
- Healthcheck on KasmVNC improves uptime monitoring reliability.

## Risks & Gaps
- Customer secrets are stored in plaintext (`data/customers.json` contains VNC passwords and Stripe IDs).
- Webhook service uses Docker socket mounting, which is powerful and risky if compromised.
- No authentication layer is enforced on customer desktops beyond VNC password.
- Lack of formal backup/restore verification; backups are referenced but not validated.
- No explicit rate limiting or abuse protections on provisioning endpoints.

## Data Protection Considerations
- Add a `.gitignore` (done) to avoid committing `data/` or `.env`.
- Consider encrypting volumes/backups at rest and documenting retention policies.
- Avoid logging sensitive values (e.g., passwords) in webhook or script outputs.

## Operational Notes
- DNS automation via Cloudflare helpers enables fast provisioning but must be guarded by least-privileged API tokens.
- Each container is isolated on its own network; Caddy is connected per customer for routing.
- The default resource limits (CPU/RAM) are reasonable for small deployments but should be stress-tested.

## Recommended Next Steps
1) Add a “Sensitive Data” section to README and document data retention/cleanup.
2) Restrict webhook endpoints with API auth and optional rate limiting.
3) Store VNC passwords in a safer way (one-time reveal, then remove from DB).
4) Add a backup verification step and disaster recovery runbook.
5) Consider moving customer records to a lightweight DB (SQLite/Postgres) when scaling.
