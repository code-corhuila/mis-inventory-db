# Inventory-Owned Event Inbox Storage

Incremental changeset inventory-event-inbox-001 adds two tables in inventory:
stock_event_inbox (immutable receipt/audit keyed by eventId) and
stock_event_checkpoint (last handled sequence per lot). Existing SQL/changesets
are unchanged; upgrading does not backfill consumer receipts or touch stock.

The intended owner API must verify incoming payload identity/sequence/lot against
its immutable source outbox and compare payload hashes on replay. It must lock the
lot checkpoint and commit inbox plus effect/checkpoint in one transaction, ignoring
stale sequences. These protocol rules are NOT implemented by the tables alone.
Foreign keys constrain references to Inventory-owned rows only, not cross-domain data.

API grants allow SELECT/INSERT, plus UPDATE of checkpoint last_sequence only.
No inbox mutation or deletion is granted. Worker will request owner effects over
HTTP, not connect to these tables. The new rollback rejects any receipt or checkpoint
so evidence cannot silently disappear. Empty-schema rollback remains test-only.

Native migration tests use an isolated database and inventory_app to insert a
synthetic receipt/checkpoint, verify grants and reject rollback with evidence.
They do not prove concurrent deduplication, HTTP authentication or actual delivery.
