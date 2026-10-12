# ADR-EVT-004: isolated relay database capabilities

Status: accepted; live login provisioning and relay activation pending.

The sixth incremental changeset creates inventory_relay as a NOLOGIN capability
role, without administrative flags or a password. It grants inventory schema
USAGE, outbox SELECT, and UPDATE only on status, attempts, next_attempt_at,
lease_token, leased_until and delivered_at. It does not inherit inventory_writer.
No privileges on stock, movements, inbox/checkpoint, event identity or payload.
Existing migrations and application permissions remain unchanged.

The PostgreSQL operator must later provision a distinct login with a file-secret
password and grant only inventory_relay, not inventory_writer or inventory_app.
Do not grant memberships through a runtime service or commit a live password.
The relay's HTTP identity remains the separate Security-issued machine subject;
database and JWT credentials are not interchangeable.

Rollback removes this capability and its grants, not stock or event evidence.
External login memberships are revoked by role removal; re-provisioning membership
after a reviewed rollback is explicit, not an automatic escalation. Test rollback
is only for a disposable project; it is not a production recovery procedure.

Test-Migrations invokes Test-RelayPermissions after creating its synthetic event.
It connects over TCP as a disposable synthetic login, verifies SELECT/FOR UPDATE
and all delivery metadata updates inside a rolled-back transaction, and checks
thirteen forbidden operations actually fail with permission denied. Stock and
pending delivery metadata are preserved. Empty rollback/rebuild, repeated update,
prior-data upgrade and outbox/inbox evidence guards remain covered with six
changesets. CI parses both scripts; native PostgreSQL acceptance runs separately.

This prepares least privilege, not a deployed relay or completed HU-EVT-001.
