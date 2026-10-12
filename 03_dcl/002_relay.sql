CREATE ROLE inventory_relay NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT USAGE ON SCHEMA inventory TO inventory_relay;
GRANT SELECT ON inventory.outbox TO inventory_relay;
GRANT UPDATE (status,attempts,next_attempt_at,lease_token,leased_until,delivered_at)
    ON inventory.outbox TO inventory_relay;
