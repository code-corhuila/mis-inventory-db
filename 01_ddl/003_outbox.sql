ALTER TABLE inventory.movement ADD COLUMN trace_id varchar(128)
    CHECK (trace_id ~ '^[A-Za-z0-9._:-]{1,128}$');
CREATE SEQUENCE inventory.outbox_sequence AS bigint;
CREATE TABLE inventory.outbox (
    event_id uuid PRIMARY KEY REFERENCES inventory.movement(id),
    sequence bigint NOT NULL UNIQUE CHECK (sequence > 0),
    lot_id uuid NOT NULL REFERENCES inventory.lot(id),
    payload jsonb NOT NULL CHECK ((jsonb_typeof(payload)='object'
        AND jsonb_exists_all(payload,ARRAY['eventId','sequence','eventType','schemaVersion','lotId','traceId','movementId'])
        AND payload->>'eventId'=event_id::text AND payload->>'movementId'=event_id::text
        AND payload->>'sequence'=sequence::text AND payload->>'lotId'=lot_id::text
        AND payload->>'eventType'='inventory.stock.changed' AND payload->>'schemaVersion'='1') IS TRUE),
    status varchar(12) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','DELIVERED')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    lease_token uuid,
    leased_until timestamptz,
    delivered_at timestamptz,
    CHECK ((lease_token IS NULL) = (leased_until IS NULL)),
    CHECK ((status='PENDING' AND delivered_at IS NULL) OR (status='DELIVERED' AND delivered_at IS NOT NULL))
);
CREATE INDEX ix_outbox_pending ON inventory.outbox(next_attempt_at,sequence) WHERE status='PENDING';
CREATE FUNCTION inventory.emit_stock_event() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE
    revision bigint;
    lot inventory.lot%ROWTYPE;
BEGIN
    SELECT * INTO STRICT lot FROM inventory.lot WHERE id=NEW.lot_id;
    revision := nextval('inventory.outbox_sequence');
    INSERT INTO inventory.outbox(event_id,sequence,lot_id,payload)
    VALUES (NEW.id,revision,NEW.lot_id,jsonb_build_object(
        'eventId',NEW.id,'eventType','inventory.stock.changed','schemaVersion',1,'sequence',revision,
        'occurredAt',to_char(NEW.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'traceId',coalesce(NEW.trace_id,NEW.id::text),'movementId',NEW.id,
        'movementType',CASE WHEN NEW.entry_id IS NOT NULL THEN 'ENTRY' ELSE 'EXIT' END,
        'lotId',lot.id,'medicationId',lot.medication_id,'supplierId',lot.supplier_id,'expiresOn',lot.expires_on,
        'quantity',NEW.quantity,'delta',CASE WHEN NEW.entry_id IS NOT NULL THEN NEW.quantity ELSE -NEW.quantity END,
        'onHandQuantity',lot.available,'entryId',NEW.entry_id,'exitId',NEW.exit_id));
    RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION inventory.emit_stock_event() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION inventory.emit_stock_event() TO inventory_writer;
GRANT SELECT ON inventory.outbox TO inventory_reader,inventory_writer;
GRANT INSERT ON inventory.outbox TO inventory_writer;
GRANT USAGE ON SEQUENCE inventory.outbox_sequence TO inventory_writer;
GRANT UPDATE (status,attempts,next_attempt_at,lease_token,leased_until,delivered_at) ON inventory.outbox TO inventory_writer;
CREATE TRIGGER movement_outbox AFTER INSERT ON inventory.movement
    FOR EACH ROW EXECUTE FUNCTION inventory.emit_stock_event();
