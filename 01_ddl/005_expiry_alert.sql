CREATE TABLE inventory.expiry_alert (
    id uuid PRIMARY KEY,
    lot_id uuid NOT NULL UNIQUE REFERENCES inventory.lot(id),
    severity varchar(8) NOT NULL CHECK (severity IN ('EXPIRING','EXPIRED')),
    state varchar(8) NOT NULL CHECK (state IN ('OPEN','RESOLVED')),
    expires_on date NOT NULL,
    on_hand_quantity bigint NOT NULL CHECK (on_hand_quantity >= 0),
    evaluated_on date NOT NULL,
    window_days smallint NOT NULL CHECK (window_days BETWEEN 1 AND 365),
    evaluated_by uuid NOT NULL,
    first_detected_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    last_evaluated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    resolved_at timestamptz,
    CHECK (last_evaluated_at >= first_detected_at),
    CHECK ((state='OPEN' AND resolved_at IS NULL) OR
           (state='RESOLVED' AND resolved_at IS NOT NULL AND
            resolved_at BETWEEN first_detected_at AND last_evaluated_at)),
    CHECK (state='RESOLVED' OR (on_hand_quantity > 0 AND
           ((severity='EXPIRED' AND expires_on <= evaluated_on) OR
            (severity='EXPIRING' AND expires_on > evaluated_on AND
             expires_on <= evaluated_on + window_days))))
);
CREATE INDEX ix_expiry_alert_state_date ON inventory.expiry_alert(state,expires_on,lot_id);
GRANT SELECT ON inventory.expiry_alert TO inventory_reader,inventory_writer;
GRANT INSERT ON inventory.expiry_alert TO inventory_writer;
GRANT UPDATE (severity,state,expires_on,on_hand_quantity,evaluated_on,window_days,
              evaluated_by,last_evaluated_at,resolved_at) ON inventory.expiry_alert TO inventory_writer;
