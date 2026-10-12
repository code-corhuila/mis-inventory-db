DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM inventory.stock_exit) THEN
        RAISE EXCEPTION 'Rollback rechazado: existen salidas confirmadas; use recuperacion con respaldo.';
    END IF;
END $$;
DROP INDEX inventory.ix_inventory_movement_order;
ALTER TABLE inventory.movement DROP CONSTRAINT ck_movement_origin;
ALTER TABLE inventory.movement DROP COLUMN exit_id;
ALTER TABLE inventory.movement ALTER COLUMN entry_id SET NOT NULL;
DROP TABLE inventory.exit_request,inventory.stock_exit;
