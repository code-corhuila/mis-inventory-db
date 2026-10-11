CREATE TABLE inventory.stock_exit (
    id uuid PRIMARY KEY,
    lot_id uuid NOT NULL REFERENCES inventory.lot(id),
    quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 1000000),
    reason varchar(200) NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 200),
    remaining_quantity bigint NOT NULL CHECK (remaining_quantity BETWEEN 0 AND 2147483647),
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL
);
CREATE TABLE inventory.exit_request (
    actor uuid NOT NULL,
    request_key varchar(128) NOT NULL CHECK (request_key ~ '^[A-Za-z0-9._:-]{8,128}$'),
    request_hash char(64) NOT NULL,
    response_json text NOT NULL,
    exit_id uuid NOT NULL REFERENCES inventory.stock_exit(id),
    PRIMARY KEY (actor,request_key)
);
ALTER TABLE inventory.movement ALTER COLUMN entry_id DROP NOT NULL;
ALTER TABLE inventory.movement ADD COLUMN exit_id uuid UNIQUE REFERENCES inventory.stock_exit(id);
ALTER TABLE inventory.movement ADD CONSTRAINT ck_movement_origin CHECK ((entry_id IS NULL) <> (exit_id IS NULL));
CREATE INDEX ix_inventory_movement_order ON inventory.movement(created_at DESC,id DESC);
GRANT SELECT ON inventory.stock_exit,inventory.exit_request TO inventory_reader,inventory_writer;
GRANT INSERT ON inventory.stock_exit,inventory.exit_request TO inventory_writer;
