DO $$ BEGIN
    IF EXISTS (SELECT FROM inventory.outbox) THEN
        RAISE EXCEPTION 'Rollback rechazado: outbox contiene eventos';
    END IF;
END $$;
DROP TRIGGER movement_outbox ON inventory.movement;
DROP FUNCTION inventory.emit_stock_event();
DROP TABLE inventory.outbox;
DROP SEQUENCE inventory.outbox_sequence;
ALTER TABLE inventory.movement DROP COLUMN trace_id;
