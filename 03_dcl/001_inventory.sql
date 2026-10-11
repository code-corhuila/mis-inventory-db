CREATE ROLE inventory_reader NOLOGIN;
CREATE ROLE inventory_writer NOLOGIN;
GRANT USAGE ON SCHEMA inventory TO inventory_reader,inventory_writer;
GRANT SELECT ON ALL TABLES IN SCHEMA inventory TO inventory_reader,inventory_writer;
GRANT INSERT ON ALL TABLES IN SCHEMA inventory TO inventory_writer;
GRANT UPDATE (available) ON inventory.lot TO inventory_writer;
GRANT UPDATE (status,changed_by,changed_at) ON inventory.entry TO inventory_writer;
GRANT inventory_writer TO inventory_app;
