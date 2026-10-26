# Release & Distribution Checklist
**Android + macOS Continuity Ecosystem**
*Version 1.0 — Go-to-Market Readiness Checklist*

---

## 1. Android Public Edition (Google Play Store)

- [ ] **Target API Compliance**: Configured for Android 15 (API level 35).
- [ ] **Permissions Review**:
  - [ ] No `MANAGE_EXTERNAL_STORAGE` declaration.
  - [ ] No `READ_SMS` or `READ_CALL_LOG` permissions requested.
  - [ ] Notification Listener declared with prominent disclosure dialog explaining user privacy.
  - [ ] Camera permission requested strictly contextually when scanning QR or starting webcam.
- [ ] **Data Safety Declarations**:
  - [ ] Data shared: None (all communications are peer-to-peer on local network).
  - [ ] Data encrypted in transit: Yes (TLS 1.3 / AES-256-GCM).
  - [ ] Account creation required: No.
- [ ] **App Bundle Packaging**: Signed `.aab` produced using Google Play App Signing key.
- [ ] **Privacy Policy**: Public URL published outlining local-first zero data collection policy.

---

## 2. macOS Application (Direct Distribution & Outside-Store)

- [ ] **Developer ID Application Certificate**: Valid Apple Developer ID Application certificate configured.
- [ ] **Hardened Runtime**: Enabled on all executable targets and framework bundles.
- [ ] **Notarization**: Submitted and successfully stapled via `xcrun notarytool`.
- [ ] **Disk Image (`.dmg`) & Gatekeeper-Friendly `.zip`**:
  - [ ] Built-in `create_zip.sh` produces `ContinuityCompanion-macOS-v${VERSION}.zip` with `ContinuityCompanion.app`, `How to Open.html`, and `/Applications` symlink.
  - [ ] macOS Gatekeeper non-technical 1-click bypass documented via embedded `x-apple.systempreferences:com.apple.preference.security` button in `How to Open.html`.
  - [ ] Styled installer DMG (`create_dmg.sh`) with Applications symlink and `How to Open.html` included.
  - [ ] Ad-hoc codesigning with `xattr -cr` applied to strip quarantine flags from local builds.
- [ ] **Entitlements Audit**: Restricted solely to network client/server, Downloads directory access, and CoreMediaIO extension.

---

## 3. Advanced Personal Edition Helper

- [ ] **scrcpy Binary Attribution**: Apache License 2.0 attribution and notice included.
- [ ] **ADB Integration**: Sandboxed subprocess management with automatic port cleanup on exit.
- [ ] **One-Click Installer**: Optional shell script / pkg for power users with clear warnings regarding USB debugging.

---

## 4. Final Security & Quality Gates

- [ ] Zero static analysis security vulnerabilities (SonarQube / Detekt / SwiftLint).
- [ ] 100% test pass rate across protocol and integration test suites.
- [ ] Battery consumption benchmark: < 1.5% battery drain per 8 hours in connected standby mode.
