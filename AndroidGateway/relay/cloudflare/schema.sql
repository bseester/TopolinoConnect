CREATE TABLE IF NOT EXISTS latest_vehicle (
  tenant_id TEXT PRIMARY KEY NOT NULL,
  envelope TEXT NOT NULL,
  received_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS vehicle_routes (
  tenant_id TEXT PRIMARY KEY NOT NULL,
  payload TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
