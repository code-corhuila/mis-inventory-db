# WRK-001 - Expiry storage acceptance

Operator-run Docker/PostgreSQL/Liquibase acceptance, 2026-10-12. Storage only,
not a live Worker or frontend alert acceptance. CI currently parses PowerShell.

The full Test-Migrations.ps1 run passed with seven changesets: first/repeated
update, empty full rollback/rebuild, upgrade preserving an older movement without
backfilling events/alerts, protected outbox/inbox evidence, and final reapplication.
Relay TCP permissions and thirteen forbidden relay operations also passed.

Test-ExpiryStorage.ps1 verified actual TCP inventory_app insertion/evaluation
updates and rejected duplicate identity, distinct identities for the same lot,
negative/zero OPEN quantities, invalid window, resolution without timestamp,
inconsistent severity/date, horizon overflow, identity/lot/first-detection mutation
and DELETE. Reader could inspect but not update; relay could not read alerts.
EXPIRING -> EXPIRED -> RESOLVED retained one row. Stock, movement and outbox
state stayed unchanged. A rejected evidence-bearing rollback preserved the exact
alert JSON and seven-entry changelog. Removing only the owned synthetic fixture
in the disposable project allowed empty rollback/reapply without fabricated alerts.

The distinct-ID/same-lot regression was additionally exercised with the complete
expiry helper in a second isolated fixture. No dev/qa/main database was migrated
or rolled back; each disposable project's own volume/network was removed.
No private environment file, password or live machine identity was committed.

Remaining: atomic owner evaluation, authenticated worker trigger/scheduling,
public alert reads, live composition alignment, frontend integration and QA.
No automatic jobs, low-stock flag activation or HU-WRK-001 closure is claimed.
