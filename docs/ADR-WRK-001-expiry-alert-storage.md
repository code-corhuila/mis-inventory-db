# ADR-WRK-001 - Owner-persisted expiry alerts

Team implementation decision, 2026-10-12. Partial HU-WRK-001, not closure.
Inventory owns stock and its expiry-alert evidence. Worker must request owner
evaluation through an authenticated API; it receives no database credentials.
This PR adds storage only, not that API, scheduler, evaluator or alert UI.

## Record and invariants

One stable record per lot represents the current expiry rule state. The unique
lot reference prevents duplicate rows; future owner evaluation must use an atomic
upsert with a stable ID, not delete/recreate evidence on every retry.
EXPIRING/EXPIRED and OPEN/RESOLVED are explicit, with retained first detection,
latest evaluation, evaluating identity and resolution timestamps. Unit quantities
are registered physical stock, not pending entries or globally aggregated units.
Snapshots are last-evaluated evidence, not guaranteed live stock.

Evaluation uses a caller-supplied business date in America/Bogota and a configurable
window of 1..365 days. Storage selects no default and schedules nothing. An OPEN
alert requires positive registered units; EXPIRED includes the expiry day itself.
EXPIRING requires expiry after that day and within the supplied window. RESOLVED
retains history and requires a non-null resolution within the evaluation timestamps.
The future owner evaluator must derive snapshots from its own locked/read-consistent
lot data, not trust caller-supplied stock values. No cross-domain FK/read is added.

## Security and migration

Only Inventory writer may insert/update evaluation fields. ID, lot identity and
first detection are not update-granted; DELETE is not granted. Inventory reader
can inspect evidence. Relay has no access; Worker has no login/grant here.
No low-stock flag, acknowledgement, manual dismissal or reactivation feature is added.

The seventh additive Liquibase changeset leaves all six earlier changesets/SQL
unchanged and creates no historical alerts. Empty rollback is allowed only in a
disposable test; any retained alert, including resolved, blocks rollback. Live
recovery needs a reviewed backup/forward migration, not deleting alert evidence.

Test-ExpiryStorage.ps1 runs only in a uniquely named mis-inv-check-* project,
checks TCP application permissions, reader/relay restrictions, transitions,
uniqueness, protected rollback and absence of stock/movement/outbox side effects.
It removes only its own synthetic alert from that disposable project to exercise
empty rollback/reapply. CI currently parses PowerShell; native Docker acceptance
is operator-run. Live root composition still needs coherent migration/deployment
alignment before the API can rely on this table.
