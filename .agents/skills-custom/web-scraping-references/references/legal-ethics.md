# Legal And Ethics Preflight

These notes are advisory. Do not make legal conclusions.

## Report Signals

Surface:

- robots.txt and ToS signals when practical
- login, paywall, captcha, anti-bot, or account risk
- personal data, sensitive data, or commercial-risk concerns
- rate-limit/cost concerns
- official API or permission path when visible

## Allowed Scout Actions Without Extra Approval

- normal HTTP requests and lightweight browser/network inspection
- embedded JSON, XHR, REST, and GraphQL discovery
- pagination probing with small sample requests
- public endpoint payload/header inspection
- risk notes and recommendations

## Ask Before Escalation

Ask before:

- login/session reuse
- private browser profile or stored cookies
- captcha handling
- proxy rotation
- fingerprint/stealth escalation
- paid APIs or paid proxy services
- high-rate crawling
- paywall access

## Preferred Safer Paths

- official API or export
- lower request rate
- caching and saved raw samples
- clear user decision on risk
- smallest sample needed for proof
