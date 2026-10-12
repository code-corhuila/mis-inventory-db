CREATE TABLE inventory.stock_event_checkpoint (
    lot_id uuid PRIMARY KEY REFERENCES inventory.lot(id),
    last_sequence bigint NOT NULL CHECK (last_sequence > 0)
);
CREATE TABLE inventory.stock_event_inbox (
    event_id uuid PRIMARY KEY REFERENCES inventory.outbox(event_id),
    lot_id uuid NOT NULL REFERENCES inventory.lot(id),
    sequence bigint NOT NULL UNIQUE CHECK (sequence > 0),
    payload_hash char(64) NOT NULL CHECK (payload_hash ~ '^[0-9a-f]{64}$'),
    applied boolean NOT NULL,
    processed_by uuid NOT NULL,
    processed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ix_stock_event_inbox_lot ON inventory.stock_event_inbox(lot_id,sequence);
GRANT SELECT ON inventory.stock_event_checkpoint,inventory.stock_event_inbox TO inventory_reader,inventory_writer;
GRANT INSERT ON inventory.stock_event_checkpoint,inventory.stock_event_inbox TO inventory_writer;
GRANT UPDATE (last_sequence) ON inventory.stock_event_checkpoint TO inventory_writer;
