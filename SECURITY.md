# Security Policy

## Reporting a Vulnerability

**Please do not report security vulnerabilities via public GitHub issues.** Instead, report them using GitHub's security advisory process:

1. Navigate to [Security Advisories](https://github.com/curdriceaurora/notes-placeholder/security/advisories)
2. Click **"New repository security advisory"**
3. Fill in the vulnerability details
4. Click **"Create draft security advisory"**

This allows the maintainers to assess the vulnerability and develop a fix before public disclosure.

### What to Include

- **Description**: Clear explanation of the vulnerability and its impact
- **Affected Versions**: Which versions of the app are vulnerable
- **Steps to Reproduce**: Minimal reproduction steps (if applicable)
- **Impact**: What could an attacker do? (data access, corruption, denial of service, etc.)
- **Suggested Fix**: If you have a fix, describe it or submit a PR

### Security Advisory Process

1. **Report received**: We acknowledge receipt within 48 hours
2. **Assessment**: We evaluate severity and impact (usually within 7 days)
3. **Development**: We develop and test a fix (timeframe depends on severity)
4. **Coordination**: We coordinate a release date with any affected downstream projects
5. **Disclosure**: We publish the advisory and release a patched version simultaneously

## Supported Versions

| Version | Supported | Notes |
|---------|-----------|-------|
| 1.x     | ✅ Current | Main development line |
| 0.x     | ❌ EOL     | No longer receiving updates |

## Known Security Limitations

### Unencrypted Local Storage

**Status**: By design
**Scope**: Local SQLite database
**Risk**: Medium (local-only; requires device access)

Notes, tasks, and sync metadata are stored in an unencrypted SQLite database at:
- macOS: `~/Library/Application Support/NotesEngine/notes.sqlite`
- iOS: App-sandboxed documents directory

**Mitigation**:
- Rely on OS file permissions and device-level encryption (FileVault on macOS, encrypted storage on iOS)
- Do not store sensitive credentials or PII beyond what sync providers expose
- Recommend users enable full-disk encryption

**Future**: Encryption at rest may be added in a future version if regulatory requirements warrant.

### EventKit Integration

**Status**: Requires explicit user permission
**Scope**: Calendar and reminder access
**Risk**: Medium (depends on underlying calendar service)

The app requests `EKEventStore` access to sync tasks with Apple Calendar. This requires explicit user authorization.

**Limitations**:
- EventKit tokens are managed by the OS; the app does not store calendar credentials
- Calendar sync relies on the security model of the underlying calendar service (local, iCloud, Google, etc.)
- Deleted tasks may leave tombstone records in the calendar if sync is interrupted

**Mitigation**:
- Users can revoke calendar access in Settings > Privacy > Calendars
- Sync operations include error handling and diagnostics for troubleshooting
- See [Docs/SYNC_ARCHITECTURE.md](Docs/SYNC_ARCHITECTURE.md) for sync design details

### Two-Way Sync Conflict Resolution

**Status**: Deterministic, last-write-wins
**Scope**: Calendar ↔ Local note/task sync
**Risk**: Low (design is transparent and reversible)

When an external calendar event and a local task conflict (edited independently):
- The conflict is detected by timestamp comparison
- Last-modified-at wins, with source tie-breaking for identical timestamps
- The losing version's state is logged in sync diagnostics (accessible in the Sync tab)

**Mitigation**:
- Users can review all sync operations and conflicts in the Sync Diagnostics tab
- Conflicts are recorded so users can manually reconcile if desired
- Timestamps are normalized for deterministic resolution

### No Multi-Device Sync

**Status**: Single-device, local-first
**Scope**: Notes and tasks
**Risk**: Low (no network exposure)

Notes and tasks are **not synced across devices**. Each device maintains an independent local database.
Only calendar integration provides any cross-device visibility (via Apple Calendar's sync).

**Future**: Multi-device sync via iCloud or similar may be added in a future version.

## Compliance & Standards

### App Permissions

The app requests the following iOS permissions (all user-prompted):
- **Calendars**: Read/write access to sync tasks with Apple Calendar
- **Reminders**: Read/write access for UserNotifications integration

Both permissions are optional; the app functions with reduced capability if denied.

### Data Handling

- **No analytics**: The app does not collect usage telemetry or analytics
- **No tracking**: No user-tracking pixels or third-party services
- **No ads**: The app contains no advertisements or ad networks
- **No cloud sync**: No data leaves the device except for calendar integration with the user's chosen calendar service

### Third-Party Dependencies

All dependencies are open-source and reviewed on inclusion:

| Package | Version | Purpose | License |
|---------|---------|---------|---------|
| `swift-markdown` | 0.5.0+ | Markdown parsing and rendering | Apache 2.0 |
| `ViewInspector` | 0.9.11+ | SwiftUI component testing (dev-only) | MIT |

**Dependency Scanning**:
- Dependencies are monitored for security advisories via GitHub's Dependabot
- Critical advisories trigger immediate review and updates
- Unused dependencies are regularly audited and removed

## Security Testing

### Test Coverage

- **Unit tests**: ≥90% code coverage on domain and storage layers
- **Integration tests**: ≥99% coverage on service protocols
- **UI tests**: Structured integration tests using ViewInspector
- **Sync tests**: Deterministic conflict resolution and round-trip behavior verified

### Continuous Integration

All commits are validated via:
1. **Lint**: SwiftLint style enforcement
2. **Build**: Swift compiler strict type checking and concurrency safety
3. **Tests**: Full XCTest suite with coverage gates
4. **Performance**: Latency budgets for critical paths (search, sync, kanban)

See [.github/workflows/](/.github/workflows/) for CI configuration.

## Security Best Practices

### For Users

1. **Keep the app updated**: Install updates as soon as available
2. **Enable device encryption**: Use FileVault (macOS) or encrypted storage (iOS)
3. **Review permissions**: Grant only necessary permissions (Calendars) in Settings
4. **Check Sync Diagnostics**: Review the Sync tab regularly for conflicts or errors
5. **Backup your data**: Export notes or sync to iCloud Calendar for redundancy

### For Contributors

1. **Principle of least privilege**: Request only necessary OS permissions
2. **Encrypt sensitive data**: Use standard encryption APIs if handling PII
3. **Avoid hardcoded secrets**: Use environment variables and secure storage
4. **Test error paths**: Handle permission denials and sync failures gracefully
5. **Document assumptions**: Note security constraints and design decisions
6. **Use HTTPS**: All network calls must use TLS 1.2+
7. **Validate input**: Sanitize user input, especially in search and sync

See [CONTRIBUTING.md](CONTRIBUTING.md) for code review and testing standards.

## Vulnerability Disclosure Timeline

We follow a 90-day coordinated disclosure window:

- **Day 0**: Vulnerability reported
- **Day 7**: Patch available (target)
- **Day 90**: Public disclosure (advisory published, patch released)

**Exceptions**:
- Critical vulnerabilities (remote code execution, data breach) may be disclosed sooner
- Low-risk vulnerabilities (information disclosure, denial of service) may be disclosed later if a patch is not yet available
- Coordination with affected downstream projects may extend the timeline

## Questions?

- **Security concern**: Use the [GitHub Security Advisory](https://github.com/curdriceaurora/notes-placeholder/security/advisories) form
- **General question**: Open an issue with the `[SECURITY]` tag or contact @curdriceaurora
- **Documentation**: Check [Docs/](Docs/) for architecture, sync design, and threat model details

---

**Last Updated**: 2026-03-03
**Version**: 1.0
