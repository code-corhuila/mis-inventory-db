DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM inventory.expiry_alert) THEN
        RAISE EXCEPTION 'Rollback rechazado: alertas de vencimiento contienen evidencia';
    END IF;
END $$;
DROP TABLE inventory.expiry_alert;
