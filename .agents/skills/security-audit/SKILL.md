---
name: security-audit
description: Superpower skill for scanning iOS app boundaries, entitlements, Keychain storage, and App Transport Security.
---

# Superpower: iOS Security & Perimeter Audit

Use this skill when auditing app entitlements, data persistence, network security, and sensitive data handling.

## Security Checklist:

### 1. Sensitive Data Storage
- Are credentials, tokens, or encryption keys stored in Keychain (`kSecClassGenericPassword`) rather than UserDefaults or unencrypted SwiftData?
- Are SwiftData stores configured with file protection (`FileProtectionType.complete`)?

### 2. App Transport Security (ATS) & Network Boundaries
- Does `Info.plist` maintain strict ATS defaults (`NSAllowsArbitraryLoads` must NOT be enabled in production)?
- Are HTTPS endpoints using TLS 1.3/1.2 with certificate validation?

### 3. Entitlements & Permissions
- Are camera, location, microphone, or photo library usage descriptions (`NSCameraUsageDescription`, etc.) clearly and accurately justified in `Info.plist`?
- Are entitlements scoped strictly to required capabilities without extraneous privileges?

### 4. Memory Scrubbing & Logging
- Ensure sensitive auth tokens or passwords are never logged via `os.Logger` or `print()`.
