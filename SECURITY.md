# Security policy

Pizzinu keeps every note on your Mac and never connects to a server. Secret notes are encrypted
with AES-256-GCM using a key derived from your password (PBKDF2-HMAC-SHA256, 1,000,000
iterations, per-note random salt, HKDF domain separation). Details in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and known limits in [docs/LIMITS.md](docs/LIMITS.md).

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Use GitHub's private
[security advisory form](https://github.com/piratepxl/pizzinu/security/advisories/new) instead.
I will reply as soon as I can and credit you in the release notes if you wish.

## Supported versions

Only the latest release receives fixes.
