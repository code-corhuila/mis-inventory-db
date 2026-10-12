param([Parameter(Mandatory)][string]$InfraRoot)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $InfraRoot).Path
$db=Split-Path $PSScriptRoot
$previousInfra=$env:MIS_INFRA_POSTGRES_PATH
$env:MIS_INFRA_POSTGRES_PATH=$repo.Replace('\','/')
$project='mis-inv-check-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$previous=$env:PG_HOST_PORT
$env:PG_HOST_PORT='0'
$options=@('--env-file',"$repo/env/dev.env",'-p',$project,'-f',"$db/deploy/compose.test.yml")
$migration=@('--changelog-file=changelog/master.yaml','--database-changelog-table-name=databasechangelog_inventory','--database-changelog-lock-table-name=databasechangeloglock_inventory')
try {
    docker compose @options up -d --wait --wait-timeout 120 postgres
    if($LASTEXITCODE -ne 0) { throw 'No inicio el PostgreSQL desechable.' }
    foreach($action in @('first','second','rollback','rebuild')) {
        if($action -eq 'rollback') { docker compose @options run --rm inventory-db-migrate @migration rollback-count --count=4 }
        else { docker compose @options run --rm inventory-db-migrate }
        if($LASTEXITCODE -ne 0) { throw "Fallo de migracion: $action" }
        $expected=if($action -eq 'rollback') {'0'} else {'4'}
        $query='SELECT count(*) FROM public.databasechangelog_inventory;'
        $count=$query | docker compose @options exec -T postgres sh -ec 'exec psql -v ON_ERROR_STOP=1 -qAt -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
        if($LASTEXITCODE -ne 0 -or $count -ne $expected) { throw 'Historial inesperado.' }
        if($action -eq 'rollback') {
            $query="SELECT count(*) FROM pg_namespace WHERE nspname='inventory';"
            $count=$query | docker compose @options exec -T postgres sh -ec 'exec psql -v ON_ERROR_STOP=1 -qAt -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
            if($LASTEXITCODE -ne 0 -or $count -ne '0') { throw 'Rollback no retiro el esquema.' }
        }
    }
    docker compose @options run --rm inventory-db-migrate @migration rollback-count --count=2
    if($LASTEXITCODE -ne 0) { throw 'No retiro migracion vacia de salidas.' }
    $query=@'
INSERT INTO inventory.lot(id,medication_id,supplier_id,lot_number,expires_on,available)
VALUES ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222','33333333-3333-3333-3333-333333333333','UPGRADE','2099-01-01',10);
INSERT INTO inventory.entry(id,lot_id,quantity,status,created_by,created_at,changed_by,changed_at)
VALUES ('44444444-4444-4444-4444-444444444444','11111111-1111-1111-1111-111111111111',10,'ACTIVE','55555555-5555-5555-5555-555555555555',now(),'55555555-5555-5555-5555-555555555555',now());
INSERT INTO inventory.movement(id,entry_id,lot_id,quantity,actor,created_at)
VALUES ('66666666-6666-6666-6666-666666666666','44444444-4444-4444-4444-444444444444','11111111-1111-1111-1111-111111111111',10,'55555555-5555-5555-5555-555555555555',now());
'@
    $query | docker compose @options exec -T postgres sh -ec 'exec psql -v ON_ERROR_STOP=1 -qAt -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
    if($LASTEXITCODE -ne 0) { throw 'No creo evidencia previa a upgrade.' }
    docker compose @options run --rm inventory-db-migrate
    if($LASTEXITCODE -ne 0) { throw 'Fallo upgrade con datos previos.' }
    $query="SELECT count(*) FROM inventory.movement WHERE entry_id IS NOT NULL AND exit_id IS NULL;"
    $count=$query | docker compose @options exec -T postgres sh -ec 'exec psql -v ON_ERROR_STOP=1 -qAt -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
    if($LASTEXITCODE -ne 0 -or $count -ne '1') { throw 'Upgrade altero movimiento existente.' }
    $count='SELECT count(*) FROM inventory.outbox;' | docker compose @options exec -T postgres sh -ec 'exec psql -v ON_ERROR_STOP=1 -qAt -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
    if($LASTEXITCODE -ne 0 -or $count -ne '0') { throw 'Upgrade genero eventos historicos no acordados.' }
    $query=@'
BEGIN;
UPDATE inventory.lot SET available=8;
INSERT INTO inventory.stock_exit(id,lot_id,quantity,reason,remaining_quantity,created_by,created_at)
VALUES ('77777777-7777-7777-7777-777777777777','11111111-1111-1111-1111-111111111111',2,'Sintetico',8,'55555555-5555-5555-5555-555555555555',now());
INSERT INTO inventory.movement(id,exit_id,lot_id,quantity,actor,created_at)
VALUES ('88888888-8888-8888-8888-888888888888','77777777-7777-7777-7777-777777777777','11111111-1111-1111-1111-111111111111',2,'55555555-5555-5555-5555-555555555555',now());
COMMIT;
'@
    $query | docker compose @options exec -T postgres sh -ec 'exec psql -v ON_ERROR_STOP=1 -qAt -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
    if($LASTEXITCODE -ne 0) { throw 'No preparo rechazo de rollback con salidas.' }
    $nativePreference=$PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference=$false
    $output=docker compose @options run --rm inventory-db-migrate @migration rollback-count --count=1 2>&1
    if($LASTEXITCODE -eq 0 -or ($output -join "`n") -notmatch 'Rollback rechazado: outbox contiene eventos') { throw 'Rollback no fue bloqueado por eventos persistidos.' }
    $PSNativeCommandUseErrorActionPreference=$nativePreference
    $query="SELECT available || ',' || (SELECT count(*) FROM inventory.stock_exit) || ',' || (SELECT count(*) FROM public.databasechangelog_inventory) FROM inventory.lot;"
    $state=$query | docker compose @options exec -T postgres sh -ec 'exec psql -v ON_ERROR_STOP=1 -qAt -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
    if($LASTEXITCODE -ne 0 -or $state -ne '8,1,4') { throw 'Rollback rechazado altero datos o historial.' }
    Write-Output 'PASS: update repetible, rollback vacio, reconstruccion, upgrade sin backfill y rechazo seguro con outbox persistido.'
} finally {
    # Se elimina exclusivamente el proyecto aleatorio de esta prueba, nunca mis-dev.
    docker compose @options down -v
    if($null -eq $previousInfra) { Remove-Item Env:MIS_INFRA_POSTGRES_PATH -ErrorAction SilentlyContinue }
    else { $env:MIS_INFRA_POSTGRES_PATH=$previousInfra }
    if($null -eq $previous) { Remove-Item Env:PG_HOST_PORT -ErrorAction SilentlyContinue }
    else { $env:PG_HOST_PORT=$previous }
}
