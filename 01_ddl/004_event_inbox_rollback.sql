DO $$ BEGIN
    IF EXISTS (SELECT FROM inventory.stock_event_inbox)
       OR EXISTS (SELECT FROM inventory.stock_event_checkpoint) THEN
        RAISE EXCEPTION 'Rollback rechazado: inbox o checkpoint contiene evidencia';
    END IF;
END $$;
DROP TABLE inventory.stock_event_inbox,inventory.stock_event_checkpoint;
