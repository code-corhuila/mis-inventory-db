REVOKE UPDATE (status,attempts,next_attempt_at,lease_token,leased_until,delivered_at)
    ON inventory.outbox FROM inventory_relay;
REVOKE SELECT ON inventory.outbox FROM inventory_relay;
REVOKE USAGE ON SCHEMA inventory FROM inventory_relay;
DROP ROLE inventory_relay;
