# mis-inventory-db

> inventory bounded context: database (schema, seeds, migrations)

Part of the **Medicine Inventory System** distributed system — team `medicine-inventory-system`, Grupo 1.
Governance and documentation live in [`mis-docs`](https://github.com/code-corhuila/mis-docs).

## Branching

Three permanent branches. **None of them accepts a direct commit** — you enter through a child
branch and leave through a Pull Request.

```
develop  <--PR--  feat/... fix/... chore/...
qa       <--PR--  qa/...
main     <--PR--  release/...  hotfix/...
```

Promotion happens **by re-application** (`git cherry-pick -x`), never by merging one permanent
branch into another: `merge develop -> qa` and `merge qa -> main` do not exist in this model.

`main` requires **1 approval from `ariel5253`**. On `develop` and `qa` the team sets its own review
rule.

Full policy: `00-governance/branching-policy.md` in `mis-docs`.

## Inventory Storage

Owns only `inventory`: lots, entries, stock exits, movements, request snapshots
and the transactional stock-change outbox. Medication and supplier UUIDs are
external references validated by APIs, not cross-domain foreign keys or reads.
The four existing Liquibase changesets and SQL files retain their applied content.
An additional fifth changeset adds the consumer inbox/checkpoint without changing them.
Historical movements are preserved without synthesizing historical events.
The outbox is storage only: no relay, consumer or alert delivery is implemented here.

## Migration Acceptance

Requires Docker Compose with `include`, PowerShell 7 and the PostgreSQL infrastructure
checkout with its ignored `env/dev.env` configured. Do not commit that file.

```powershell
./tests/Test-Migrations.ps1 -InfraRoot 'D:\descargas\pago 2\mis-infra-postgres'
```

The script creates a random isolated PostgreSQL project, checks repeated update,
empty rollback/rebuild, upgrade preserving a prior movement without backfill,
and rejection of rollback after an event exists. Only its own test volume is removed.
It does not test API authentication, concurrent stock writes or event delivery.
CI parses the acceptance script; real Docker acceptance is run separately.

## Deployment Boundary

`deploy/compose.yml` contributes a one-shot Liquibase job to the shared PostgreSQL
root composition; it does not create another database engine. The migration job
uses administrator credentials supplied through infrastructure environment variables.
This existing mechanism is retained, not claimed to provide file-secret isolation;
runtime services must use their restricted application identity instead.
Rollback guards reject persisted outbox events and confirmed exits. The initial
schema rollback is destructive and is exercised only on an empty disposable database.
Production recovery requires a reviewed backup/forward migration, not this test script.

## Event Inbox Preparation

`inventory.stock_event_inbox` and `inventory.stock_event_checkpoint` prepare
Inventory-owned receipt/audit and per-lot ordering storage. The owner API's atomic
deduplication/effect logic is implemented separately; these tables alone do not
prove delivery or close HU-EVT-001. See docs/ADR-EVT-003-inbox-storage.md.
Migration acceptance also checks empty inbox rollback, retained evidence on
rejected rollback, and restricted grants using the actual inventory_app login.
