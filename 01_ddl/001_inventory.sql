CREATE SCHEMA inventory;
CREATE TABLE inventory.lot (
    id uuid PRIMARY KEY,
    medication_id uuid NOT NULL,
    supplier_id uuid NOT NULL,
    lot_number varchar(40) NOT NULL CHECK (lot_number ~ '^[A-Z0-9-]{1,40}$'),
    expires_on date NOT NULL,
    available bigint NOT NULL DEFAULT 0 CHECK (available BETWEEN 0 AND 2147483647),
    CONSTRAINT uq_inventory_lot UNIQUE (medication_id,supplier_id,lot_number)
);
CREATE TABLE inventory.entry (
    id uuid PRIMARY KEY,
    lot_id uuid NOT NULL REFERENCES inventory.lot(id),
    quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 1000000),
    status varchar(12) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','ACTIVE','CANCELLED')),
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL,
    changed_by uuid,
    changed_at timestamptz,
    CHECK ((status='PENDING' AND changed_by IS NULL AND changed_at IS NULL)
        OR (status<>'PENDING' AND changed_by IS NOT NULL AND changed_at IS NOT NULL))
);
CREATE INDEX ix_inventory_entry_order ON inventory.entry(created_at DESC,id DESC);
CREATE TABLE inventory.movement (
    id uuid PRIMARY KEY,
    entry_id uuid NOT NULL UNIQUE REFERENCES inventory.entry(id),
    lot_id uuid NOT NULL REFERENCES inventory.lot(id),
    quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 1000000),
    actor uuid NOT NULL,
    created_at timestamptz NOT NULL
);
CREATE TABLE inventory.request (
    actor uuid NOT NULL,
    operation varchar(12) NOT NULL CHECK (operation IN ('prepare','activate','cancel')),
    request_key varchar(128) NOT NULL CHECK (request_key ~ '^[A-Za-z0-9._:-]{8,128}$'),
    request_hash char(64) NOT NULL,
    response_json text NOT NULL,
    entry_id uuid NOT NULL REFERENCES inventory.entry(id),
    PRIMARY KEY (actor,operation,request_key)
);
