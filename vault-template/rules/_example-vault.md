---
title: No secrets in vault notes
scope: vault
priority: high
enforcement: advise
created: 2026-04-21
updated: 2026-04-21
status: active
---

**Rule:** Never write API keys, tokens, passwords, connection strings, private URLs, `.env` contents, or long hex/base64 blobs into any file under `~/vault/`. Replace with `[REDACTED]`.

**Why:** Vault is plaintext-searchable and synced to git — treat as public-visible even if the repo is private. The `vault-secret-guard.sh` PreToolUse hook enforces this structurally, but the rule exists so Claude redacts proactively before triggering the block.

**How to apply:** Any Write/Edit/MultiEdit into `~/vault/`. Scan the content for secret patterns (`sk-…`, `ghp_…`, `AKIA…`, `Bearer …`, `password=`, `-----BEGIN …PRIVATE KEY-----`) before submitting the tool call.
