param([Parameter(Mandatory)][string[]]$ComposeOptions)
$ErrorActionPreference='Stop'
$previous=$PSNativeCommandUseErrorActionPreference
function Admin([string]$query) {
    $result=$query | docker compose @ComposeOptions exec -T postgres sh -ec 'exec psql -v ON_ERROR_STOP=1 -qAt -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
    if($LASTEXITCODE -ne 0) { throw 'Fallo preparacion o comprobacion administrativa del fixture.' }
    return $result
}
function Relay([string]$query) {
    # This credential belongs only to the disposable test database, never to a live environment.
    $result=$query | docker compose @ComposeOptions exec -T postgres sh -ec 'export PGPASSWORD="synthetic-relay-only"; exec psql -h 127.0.0.1 -v ON_ERROR_STOP=1 -qAt -U inventory_relay_fixture -d "$POSTGRES_DB"' 2>&1
    return $result
}
try {
    $PSNativeCommandUseErrorActionPreference=$false
    Admin "CREATE ROLE inventory_relay_fixture LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD 'synthetic-relay-only'; GRANT inventory_relay TO inventory_relay_fixture;" | Out-Null
    $query=@'
BEGIN;
SELECT current_user;
SELECT count(*) FROM inventory.outbox;
SELECT count(*) FROM (SELECT event_id FROM inventory.outbox FOR UPDATE SKIP LOCKED LIMIT 1) reserved;
UPDATE inventory.outbox SET status='DELIVERED',attempts=1,next_attempt_at=clock_timestamp(),
    lease_token=NULL,leased_until=NULL,delivered_at=clock_timestamp();
ROLLBACK;
'@
    $result=Relay $query
    if($LASTEXITCODE -ne 0 -or ($result -join ',') -ne 'inventory_relay_fixture,1,1') { throw 'Relay no pudo autenticarse, reservar o actualizar metadatos.' }
    foreach($query in @(
        'SELECT * FROM inventory.lot;',
        'UPDATE inventory.lot SET available=0;',
        'UPDATE inventory.outbox SET payload=payload;',
        'UPDATE inventory.outbox SET event_id=event_id;',
        'UPDATE inventory.outbox SET sequence=sequence;',
        'UPDATE inventory.outbox SET lot_id=lot_id;',
        'DELETE FROM inventory.outbox;',
        'INSERT INTO inventory.outbox SELECT * FROM inventory.outbox WHERE false;',
        'INSERT INTO inventory.stock_event_inbox SELECT * FROM inventory.stock_event_inbox WHERE false;',
        'DELETE FROM inventory.stock_event_inbox;',
        'UPDATE inventory.stock_event_checkpoint SET last_sequence=last_sequence;',
        'CREATE TABLE inventory.relay_should_not_exist(id integer);',
        'SET ROLE inventory_writer;'
    )) {
        $result=Relay ("BEGIN;`n"+$query+"`nROLLBACK;")
        if($LASTEXITCODE -eq 0 -or ($result -join "`n") -notmatch 'permission denied') { throw "Operacion prohibida no fue rechazada por permisos: $query" }
    }
    $state=Admin "SELECT available || ',' || (SELECT count(*) FROM inventory.outbox WHERE status='PENDING' AND attempts=0) FROM inventory.lot;"
    if($state -ne '8,1') { throw 'Pruebas de permisos alteraron saldo o evento.' }
    $flags=Admin "SELECT rolcanlogin::int || ',' || rolsuper::int || ',' || rolcreatedb::int || ',' || rolcreaterole::int || ',' || rolreplication::int || ',' || rolbypassrls::int FROM pg_roles WHERE rolname='inventory_relay';"
    if($flags -ne '0,0,0,0,0,0') { throw 'Rol de capacidades excesivo.' }
    Write-Output 'PASS: login TCP sintetico, reserva/metadatos y trece operaciones prohibidas rechazadas.'
} finally { $PSNativeCommandUseErrorActionPreference=$previous }
