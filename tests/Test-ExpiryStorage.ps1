param([Parameter(Mandatory)][string[]]$ComposeOptions,[Parameter(Mandatory)][string[]]$MigrationOptions)
$ErrorActionPreference='Stop'
$projectFlags=@(0..($ComposeOptions.Count-1) | Where-Object { $ComposeOptions[$_] -eq '-p' })
if ($projectFlags.Count -ne 1 -or $projectFlags[0]+1 -ge $ComposeOptions.Count -or $ComposeOptions[$projectFlags[0]+1] -notmatch '^mis-inv-check-[0-9a-f]{8}$') { throw 'Esta prueba solo admite su proyecto desechable.' }
function Sql([string]$Query,[switch]$Application) {
    if ($Application) { $result=$Query | docker compose @ComposeOptions exec -T postgres sh -ec 'export PGPASSWORD="$INVENTORY_APP_PASSWORD"; exec psql -h 127.0.0.1 -v ON_ERROR_STOP=1 -qAt -U inventory_app -d "$POSTGRES_DB"' }
    else { $result=$Query | docker compose @ComposeOptions exec -T postgres sh -ec 'exec psql -v ON_ERROR_STOP=1 -qAt -U "$POSTGRES_USER" -d "$POSTGRES_DB"' }
    if ($LASTEXITCODE -ne 0) { throw 'Fallo SQL de aceptacion de alertas.' }
    return ($result -join ',')
}
function Denied([string]$Query,[string]$Reason,[switch]$Application) {
    $previous=$PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference=$false
        if ($Application) { $result=$Query | docker compose @ComposeOptions exec -T postgres sh -ec 'export PGPASSWORD="$INVENTORY_APP_PASSWORD"; exec psql -h 127.0.0.1 -v ON_ERROR_STOP=1 -qAt -U inventory_app -d "$POSTGRES_DB"' 2>&1 }
        else { $result=$Query | docker compose @ComposeOptions exec -T postgres sh -ec 'exec psql -v ON_ERROR_STOP=1 -qAt -U "$POSTGRES_USER" -d "$POSTGRES_DB"' 2>&1 }
        if ($LASTEXITCODE -eq 0 -or ($result -join "`n") -notmatch $Reason) { throw "Rechazo SQL no comprobado: $Reason" }
    } finally { $PSNativeCommandUseErrorActionPreference=$previous }
}
$before=Sql "SELECT (SELECT available FROM inventory.lot LIMIT 1) || ',' || (SELECT count(*) FROM inventory.movement) || ',' || (SELECT count(*) FROM inventory.outbox);"
$insert=@'
INSERT INTO inventory.expiry_alert(id,lot_id,severity,state,expires_on,on_hand_quantity,evaluated_on,window_days,evaluated_by)
VALUES ('99999999-9999-4999-8999-999999999999','11111111-1111-1111-1111-111111111111','EXPIRING','OPEN','2099-01-01',8,'2098-12-31',30,'55555555-5555-5555-5555-555555555555');
'@
Sql $insert -Application | Out-Null
Denied $insert 'duplicate key' -Application
Denied ($insert.Replace('99999999-9999-4999-8999-999999999999','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')) 'expiry_alert_lot_id_key' -Application
Denied "UPDATE inventory.expiry_alert SET on_hand_quantity=-1;" 'check constraint' -Application
Denied "UPDATE inventory.expiry_alert SET on_hand_quantity=0;" 'check constraint' -Application
Denied "UPDATE inventory.expiry_alert SET window_days=0;" 'check constraint' -Application
Denied "UPDATE inventory.expiry_alert SET state='RESOLVED';" 'check constraint' -Application
Denied "UPDATE inventory.expiry_alert SET severity='EXPIRED';" 'check constraint' -Application
Denied "UPDATE inventory.expiry_alert SET expires_on='2099-03-01';" 'check constraint' -Application
Denied "UPDATE inventory.expiry_alert SET id=gen_random_uuid();" 'permission denied' -Application
Denied "UPDATE inventory.expiry_alert SET lot_id=gen_random_uuid();" 'permission denied' -Application
Denied "UPDATE inventory.expiry_alert SET first_detected_at=clock_timestamp();" 'permission denied' -Application
Denied "DELETE FROM inventory.expiry_alert;" 'permission denied' -Application
Denied "SET ROLE inventory_relay; SELECT * FROM inventory.expiry_alert;" 'permission denied'
Denied "SET ROLE inventory_reader; UPDATE inventory.expiry_alert SET on_hand_quantity=0;" 'permission denied'
if ((Sql "SET ROLE inventory_reader; SELECT count(*) FROM inventory.expiry_alert;") -ne '1') { throw 'Reader no pudo consultar evidencia.' }
$beforeAlert=Sql 'SELECT row_to_json(a)::text FROM inventory.expiry_alert a;'
$previous=$PSNativeCommandUseErrorActionPreference
try {
    $PSNativeCommandUseErrorActionPreference=$false
    $output=docker compose @ComposeOptions run --rm inventory-db-migrate @MigrationOptions rollback-count --count=1 2>&1
    if ($LASTEXITCODE -eq 0 -or ($output -join "`n") -notmatch 'ERROR: Rollback rechazado: alertas de vencimiento contienen evidencia') { throw 'Rollback no protegio alerta persistida.' }
} finally { $PSNativeCommandUseErrorActionPreference=$previous }
if ((Sql 'SELECT row_to_json(a)::text FROM inventory.expiry_alert a;') -ne $beforeAlert -or (Sql 'SELECT count(*) FROM public.databasechangelog_inventory;') -ne '7') { throw 'Rollback rechazado altero alerta o historial.' }
Sql "UPDATE inventory.expiry_alert SET severity='EXPIRED',evaluated_on='2099-01-01',last_evaluated_at=clock_timestamp() WHERE id='99999999-9999-4999-8999-999999999999';" -Application | Out-Null
Sql "UPDATE inventory.expiry_alert SET state='RESOLVED',on_hand_quantity=0,resolved_at=now(),last_evaluated_at=now() WHERE id='99999999-9999-4999-8999-999999999999';" -Application | Out-Null
if ((Sql "SELECT count(*) || ',' || min(state) FROM inventory.expiry_alert;") -ne '1,RESOLVED') { throw 'Transicion genero duplicados o no resolvio alerta.' }
if ((Sql "SELECT (SELECT available FROM inventory.lot LIMIT 1) || ',' || (SELECT count(*) FROM inventory.movement) || ',' || (SELECT count(*) FROM inventory.outbox);") -ne $before) { throw 'Persistir alerta altero stock/movimientos/outbox.' }
# Solo se retira el fixture propio del proyecto desechable para probar rollback vacio.
Sql "DELETE FROM inventory.expiry_alert WHERE id='99999999-9999-4999-8999-999999999999';" | Out-Null
docker compose @ComposeOptions run --rm inventory-db-migrate @MigrationOptions rollback-count --count=1
if ($LASTEXITCODE -ne 0 -or (Sql 'SELECT count(*) FROM public.databasechangelog_inventory;') -ne '6') { throw 'Rollback vacio no regreso a seis changesets.' }
docker compose @ComposeOptions run --rm inventory-db-migrate
if ($LASTEXITCODE -ne 0 -or (Sql 'SELECT count(*) FROM inventory.expiry_alert;') -ne '0') { throw 'Reaplicar migracion genero alertas ficticias.' }
Write-Output 'PASS: alertas unicas, transiciones, restricciones, permisos, rollback con evidencia protegido y reaplicacion sin backfill.'
