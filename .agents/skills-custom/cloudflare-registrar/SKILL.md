---
name: cloudflare-registrar
description: "Cloudflare Registrar: domain availability, prices, registration via mcporter."
---

# Cloudflare Registrar

Use for Cloudflare Registrar domain availability, pricing, listing, and registration.

## Defaults

- MCP: `cloudflare-openclaw`
- Account: `OPENCLAW_CLOUDFLARE_ACCOUNT_ID`
- Token: `OPENCLAW_CLOUDFLARE_API_TOKEN`
- Secrets: follow the root secret rule; export only needed Cloudflare vars for one command.

## Guardrails

- Always run `domain-check` immediately before registration.
- Registration is billable/non-refundable. Ask Peter for explicit confirmation before `POST /registrar/registrations`.
- Do not print tokens.

## Commands

Check availability/pricing:

```bash
npx mcporter call cloudflare-openclaw.execute code='async () => {
  return cloudflare.request({
    method: "POST",
    path: `/accounts/${accountId}/registrar/domain-check`,
    body: { domains: ["example.com"] }
  });
}'
```

Register after confirmation:

```bash
npx mcporter call cloudflare-openclaw.execute code='async () => {
  return cloudflare.request({
    method: "POST",
    path: `/accounts/${accountId}/registrar/registrations`,
    body: { domain_name: "example.com", auto_renew: false, privacy_mode: "redaction" }
  });
}'
```

List registrations:

```bash
npx mcporter call cloudflare-openclaw.execute code='async () => {
  return cloudflare.request({
    method: "GET",
    path: `/accounts/${accountId}/registrar/registrations`
  });
}'
```
