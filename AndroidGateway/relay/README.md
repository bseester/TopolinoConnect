# Topolino Gateway internet relay

This project includes a Cloudflare Worker + D1 relay for sending the Android car-phone's latest ESP CAN sample and Android-owned route history to the iPhone across different networks. It implements:

- `POST /api/v1/vehicle/latest` accepts the latest ESP CAN envelope received over BLE or USB-OTG.
- `GET /api/v1/vehicle/latest` returns the most recent sample with a freshness flag.
- `GET /api/v1/vehicle/routes` returns Android's saved trips and last parked location for the same access key.
- `PUT /api/v1/vehicle/routes` syncs the complete route snapshot, including GPS points, odometer, battery/range start and end values, and park time/location.
- `GET /health` is a simple deployment check.

The relay stores the latest vehicle envelope and route-history snapshot per access key in D1. It stores a SHA-256 hash of the access key as the account slot, not the key itself. Android syncs route history periodically and after route/park changes. Route coordinates are stored in D1 to make the same history available to iOS.

## Deploy from Cloudflare Dashboard

1. Sign in to your Cloudflare account.
2. Open **Storage & Databases → D1 SQL Database**, create a database named `topolino-gateway-relay`.
3. Run `cloudflare/schema.sql` in the database **Console**. It creates the active latest-sample and route-snapshot tables.
4. Open **Workers & Pages**, create a Worker named `topolino-gateway-relay`, then choose **Edit code**.
5. Replace the starter script with the full contents of `cloudflare/src/index.mjs` and deploy it.
6. Open the Worker **Settings → Bindings**, add a **D1 database** binding with variable name `DB`, and select `topolino-gateway-relay`. Save and deploy the Worker again if prompted.
7. In the Worker's settings, enable its `workers.dev` route if Cloudflare has not enabled it. Copy its public HTTPS address, for example `https://topolino-gateway-relay.<your-subdomain>.workers.dev`.
8. Visit `<worker-url>/health`; it should return `{"ok":true,"service":"Topolino Gateway Relay"}`.

## Connect the apps

1. On the Android car phone, open **Topolino Gateway → Internet rölesi**. The Worker HTTPS address is prefilled; confirm it is `https://topolino-gateway-relay.88doruk55.workers.dev`. Leave the gateway service running and keep ESP32 BLE advertising enabled.
2. In the Android app, copy the **X-Topolino-Key** using its copy-key action.
3. In iOS, open **Diğer → Android araç telefonu**. The Worker HTTPS address is prefilled; paste the copied access key, save, then enable the Android gateway.
4. Keep the access key private. Do not post it in chat or screenshots. If it is exposed, regenerate it before continuing.

The iPhone checks every 15 seconds when live data is present and backs off while the car has no fresh sample. Android publishes the ESP CAN values received from the ESP32; it does not poll or transmit while the ESP has stopped advertising. The relay cannot wake the car or ESP32.

## Optional Wrangler deployment

The `cloudflare/wrangler.toml` file is a CLI template. Create the D1 database with Wrangler, replace `database_id` with the returned ID, run the schema against that database, then deploy from the `cloudflare` folder. Wrangler login and Cloudflare account approval are user-side steps.

## Data and limits

The D1 database keeps the latest envelope and the current route-history snapshot per access key. Stale vehicle samples are marked as last-known after 45 seconds. Cloudflare's free-tier limits and terms can change, so check its current Workers and D1 pricing pages before relying on a free quota. There is no Cloudflare account or live deployment configured by this repository.
