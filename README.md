# Rogainizer Infrastructure

## All the required secrets are found in .env.notes (which of course is not in this repo). You need to get this file from the current maintainer of the source

Basic full-stack setup with:

- Vue 3 + Vite frontend (`frontend`)
- Node.js + Express API (`backend`)
- MySQL database connection via `mysql2`

## Prerequisites

- Node.js 20+
- npm 10+
- MySQL 8+
- Docker Desktop (for containerized setup)

## 1) Configure database

Create schema/table in MySQL:

```sql
SOURCE backend/sql/init.sql;
```

## 2) Configure backend env

Copy `backend/.env.example` to `backend/.env` and set values.

To enable protected edit actions, set backend auth values in `backend/.env`:

- `AUTH_USERNAME`
- `AUTH_PASSWORD`
- `AUTH_SECRET`
- `AUTH_TTL_HOURS`

## 3) Install dependencies

From repo root:

```bash
npm install
npm install --prefix backend
```

The frontend dependencies are already installed by Vite scaffolding. If needed:

```bash
npm install --prefix frontend
```

## 4) Run app

From repo root:

```bash
npm run dev
```

- API: http://localhost:3000
- Frontend: http://localhost:5173

To run only the frontend in dev mode against a deployed backend API instead of the local API:

1. Copy `frontend/.env.remote-api.example` to `frontend/.env.remote-api.local`
2. Set `VITE_API_BASE_URL` to the deployed backend URL
3. Run `npm run dev:web:remote-api`

Mobile leaderboards-only view (phone-friendly):

- Automatically enabled when viewport width is `900px` or smaller.
- Optional force-mobile URL: `http://localhost:5173/?mobile=1`
- Optional force-desktop URL: `http://localhost:5173/?mobile=0`

## Run frontend/backend locally against the production MySQL database

Use an SSH tunnel instead of connecting to the droplet's MySQL port directly.

One-command Windows launcher from repo root:

```powershell
npm run dev:prod-db
```

This starts the tunnel and then runs the existing local frontend/backend dev stack.

To pass tunnel parameters through npm:

```powershell
npm run dev:prod-db -- -DropletUser ubuntu -IdentityFile ~/.ssh/id_ed25519
```

1. Open a terminal and start the tunnel from repo root:

```powershell
./deploy/open-prod-db-tunnel.ps1
```

Optional parameters:

- `-DropletUser ubuntu`
- `-IdentityFile ~/.ssh/id_ed25519`
- `-LocalPort 3307`

2. Point the local backend at the tunneled port by setting `backend/.env` like this:

```env
PORT=3000
DB_HOST=127.0.0.1
DB_PORT=3307
DB_USER=<prod_app_user>
DB_PASSWORD=<prod_app_password>
DB_NAME=rogainizer
AUTH_USERNAME=<local_admin_user>
AUTH_PASSWORD=<local_admin_password>
AUTH_SECRET=<local_auth_secret>
AUTH_TTL_HOURS=12
```

Use the production app DB credentials from `.env.notes` or the maintainer-managed production env.

3. Start the local app from repo root:

```bash
npm run dev
```

This gives you:

- Frontend: `http://localhost:5173`
- Local backend: `http://localhost:3000`
- Database path: `127.0.0.1:3307` -> SSH tunnel -> prod droplet MySQL

If you want to inspect the production database directly from a local MySQL client, connect it to host `127.0.0.1`, port `3307`, using the same app credentials.

To create a local backup file from the production database on Windows:

```powershell
./deploy/backup-prod-db-local.ps1 -IdentityFile C:/Users/dougl/.ssh/rogainizer-prod
```

By default this downloads the backup into `deploy/backups` and removes the temporary remote file after download.

## Run with Docker Compose

From repo root:

```bash
docker compose up --build
```

If frontend dependencies change (for example after adding Tailwind), refresh the Docker `web` node_modules volume once:

```bash
npm run docker:web:deps
```

Then run Compose normally:

```bash
docker compose up --build
```

This starts:

- `db` (MySQL 8.4) on port `3306`
- `api` (Express) on port `3000`
- `web` (Vite + Vue) on port `5173`

The MySQL schema and `events` table are initialized automatically from `backend/sql/init.sql`.

Stop and remove containers:

```bash
docker compose down
```

Stop and remove containers + DB volume:

```bash
docker compose down -v
```

View logs:

```bash
docker compose logs -f
```

## Production deploy (single VPS, low-cost)

This repository includes production deployment artifacts for a single VPS:

- `docker-compose.prod.yml`
- `deploy/Caddyfile`
- `frontend/Dockerfile.prod`
- `.env.production.example`

### 0) Create the DigitalOcean VPS (Droplet)

1. In DigitalOcean, create a new Droplet:
	- Region: closest to your users
	- Image: Ubuntu 22.04 LTS or newer
	- Size: Basic shared CPU (start with 1 vCPU / 1 GB for low volume)
2. Add SSH key authentication (recommended) and disable password login if possible.
3. In **Advanced Options**:
	- Paste one of the provided cloud-init files into User Data, or leave blank for manual setup.
4. Create the droplet and note the public IPv4 address.
5. Point your domain DNS `A` record to that IPv4.
6. Wait for DNS to propagate before expecting TLS certificate issuance.

If you used cloud-init, initial provisioning starts automatically on first boot.
If you did not use cloud-init, install Docker + Compose plugin manually before continuing.

Optional: create the droplet via API using the included script:

```bash
export DO_API_TOKEN=<your_digitalocean_token>
chmod +x deploy/create-do-droplet.sh
./deploy/create-do-droplet.sh --name rogainizer-prod --region syd1 --ssh-keys "<ssh_key_id_or_fingerprint>"
```

PowerShell (Windows):

```powershell
$env:DO_API_TOKEN = "<your_digitalocean_token>"
./deploy/create-do-droplet.ps1 -Name rogainizer-prod -Region syd1 -SshKeys "<ssh_key_id_or_fingerprint>"
```

Password-login option (no SSH key):

```bash
export DO_API_TOKEN=<your_digitalocean_token>
./deploy/create-do-droplet.sh \
	--name rogainizer-prod \
	--region syd1 \
	--password-user ubuntu \
	--password-pass '<strong_password>'
```

```powershell
$env:DO_API_TOKEN = "<your_digitalocean_token>"
./deploy/create-do-droplet.ps1 -Name rogainizer-prod -Region syd1 -PasswordUser ubuntu -PasswordPass "<strong_password>"
```

Security note: SSH keys are recommended for production. If you enable password login, use a strong password and rotate it after first login.

The script reads `deploy/digitalocean-cloud-init-autodeploy.yaml` by default and prints droplet ID + public IPv4.

### 1) Prepare server

- Ubuntu 22.04+ VPS with Docker + Compose plugin installed
- DNS `A` record for your domain pointing to the VPS IP
- Open ports `80` and `443` in firewall/security group

DigitalOcean cloud-init options are included:

- `deploy/digitalocean-cloud-init.yaml` (bootstrap only)
- `deploy/digitalocean-cloud-init-autodeploy.yaml` (bootstrap + clone + deploy)
- `deploy/digitalocean-cloud-init-autodeploy-private.yaml` (bootstrap + private repo clone + deploy)

Supported autodeploy variants are:

- `deploy/digitalocean-cloud-init-autodeploy.yaml`
- `deploy/digitalocean-cloud-init-autodeploy-private.yaml`

If you use the auto-deploy variant, edit placeholders before creating the droplet:

- `REPO_URL`
- `REPO_REF`
- `DOMAIN`
- `MYSQL_ROOT_PASSWORD`
- `DB_PASSWORD`

After droplet creation, verify:

```bash
sudo tail -f /var/log/rogainizer-autodeploy.log
docker ps
```

For private repositories:

1. Create a GitHub deploy key with read access and add it to your repository.
2. Base64-encode the private key and set `GITHUB_DEPLOY_KEY_BASE64` in `deploy/digitalocean-cloud-init-autodeploy-private.yaml`.
3. Set `REPO_URL` to SSH format (for example `git@github.com:owner/repo.git`).

Base64 examples:

```bash
# Linux/macOS
base64 -w 0 ~/.ssh/id_ed25519

# PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.ssh\id_ed25519"))
```

### 2) Configure environment

From repo root:

```bash
cp .env.production.example .env.production
```

Edit `.env.production` and set:

- `DOMAIN` (for TLS certificate)
- `MYSQL_ROOT_PASSWORD`
- `DB_USER` (recommended: non-root, for example `rogainizer_app`)
- `DB_PASSWORD`

Create/update a dedicated MySQL app user with least-privilege grants:

```bash
cd /opt/rogainizer
chmod +x deploy/create-db-app-user.sh
./deploy/create-db-app-user.sh .env.production
```

This script grants `SELECT, INSERT, UPDATE, DELETE` on `${DB_NAME}.*` to `${DB_USER}`.

### 3) Start production stack

```bash
docker compose \
	--env-file .env.production \
	-f docker-compose.prod.yml \
	up -d --build
```

This runs:

- `db` (internal only)
- `api` on internal network (`npm start`)
- `web` as static nginx serving built Vite output
- `proxy` (Caddy) handling HTTPS and routing `/api/*` to backend

### 3b) Apply small-VM MySQL tuning

```bash
cd /opt/rogainizer
chmod +x deploy/tune-mysql-small-vm.sh
./deploy/tune-mysql-small-vm.sh .env.production
```

This script writes `deploy/mysql/99-rogainizer-small-vm.cnf`, restarts the `db` service, and verifies settings after restart.

Applied settings:

- `innodb_buffer_pool_size=134217728` (128 MB)
- `max_connections=25`
- `table_open_cache=128`
- `thread_cache_size=4`
- `tmp_table_size=16777216` (16 MB)
- `max_heap_table_size=16777216` (16 MB)
- `innodb_stats_on_metadata=OFF`
- `performance_schema=OFF` (startup setting)

Autodeploy cloud-init variants run this tuning script automatically.

### 4) Initialize schema (first deploy)

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml exec api npm run db:init
```

### 5) Verify

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml ps
docker compose --env-file .env.production -f docker-compose.prod.yml logs -f proxy
```

Then open `https://your-domain`.

### 5b) Post-deploy self-check (PASS/FAIL)

`deploy/postdeploy-check.sh` validates:

- DNS resolution for `DOMAIN`
- HTTPS/TLS reachability for `https://DOMAIN`
- API health endpoint (`/api/health`)
- Direct DB connectivity via `mysqladmin ping`

Run manually:

```bash
cd /opt/rogainizer
chmod +x deploy/postdeploy-check.sh
./deploy/postdeploy-check.sh .env.production
```

Output ends with either:

- `SUMMARY PASS`
- `SUMMARY FAIL count=<n>`

### 5c) First-boot report file

Autodeploy variants also generate:

- `/var/log/rogainizer-report.txt`

The report includes timestamp, host/kernel, Docker/Compose versions, container status, and health check output.

Regenerate manually:

```bash
cd /opt/rogainizer
chmod +x deploy/first-boot-report.sh
./deploy/first-boot-report.sh .env.production /var/log/rogainizer-report.txt
cat /var/log/rogainizer-report.txt
```

### 6) Nightly database backups

Backup assets are included:

- `deploy/backup-db.sh`
- `deploy/backup-db.cron.example`

On VPS:

```bash
chmod +x /opt/rogainizer/deploy/backup-db.sh
cp /opt/rogainizer/deploy/backup-db.cron.example /tmp/rogainizer-cron
crontab /tmp/rogainizer-cron
```

Run a manual backup test:

```bash
cd /opt/rogainizer
./deploy/backup-db.sh
ls -lh deploy/backups
```

By default backups older than 14 days are deleted. Override with:

```bash
RETENTION_DAYS=30 ./deploy/backup-db.sh
```

Restore from a backup:

```bash
gunzip -c deploy/backups/<your-backup>.sql.gz \
	| docker compose --env-file .env.production -f docker-compose.prod.yml exec -T db sh -lc "exec mysql -uroot -p\"$MYSQL_ROOT_PASSWORD\""
```

## Troubleshooting bundle

Generate a support bundle tarball with redacted env, compose status, key service logs, and health output:

```bash
cd /opt/rogainizer
chmod +x deploy/collect-support-bundle.sh
./deploy/collect-support-bundle.sh .env.production
ls -lh deploy/support/*.tar.gz
```

Optional output directory:

```bash
./deploy/collect-support-bundle.sh .env.production /tmp/rogainizer-support
```

Lightweight bundle (skip service logs):

```bash
./deploy/collect-support-bundle.sh .env.production /tmp/rogainizer-support --no-logs
```

Smaller log bundle (include logs but limit lines):

```bash
./deploy/collect-support-bundle.sh .env.production /tmp/rogainizer-support --tail 200
```

## CI/CD deployment

- Workflow file: `.github/workflows/deploy-prebuilt.yml` (manual dispatch `Production Deploy`)
- Secrets required:
	- `DROPLET_IP`: public IPv4 of the production droplet
	- `DROPLET_SSH_KEY`: private deploy key used for SSH
	- `GHCR_USERNAME`: account that owns the container images (usually the repo owner)
	- `GHCR_TOKEN`: PAT for that account with at least `read:packages` + `write:packages`
	- `SMTP_USERNAME`: Gmail address (must have app password enabled - https://myaccount.google.com/apppasswords)
	- `SMTP_PASSWORD`: Gmail app password for SMTP auth
- Workflow stages:
	1. Build backend/frontend images with `docker compose -f docker-compose.prod.yml build api web`.
	2. Tag/push images to GHCR with both `latest` and commit SHA tags.
	3. SSH into the droplet, pull those prebuilt images, restart the stack, and run `npm run db:init`.
	4. Execute `deploy/postdeploy-check.sh .env.production`, store logs/status on the droplet, scp them back, and email the results to `rogainizer.nz@gmail.com`.
- The droplet login to GHCR relies on `GHCR_USERNAME`/`GHCR_TOKEN`. Generate the token from https://github.com/settings/tokens (classic PAT) and enable `read:packages` and `write:packages` scopes so it can pull/push images.

### Preparing the deploy key

Run the helper script from the project root to generate key material and install the public key on the droplet:

```powershell
./deploy/setup-deploy-key.ps1 -DropletIp <droplet_ip>
```

What the script does:

1. Generates an ed25519 key pair inside `.deploy-keys/` (ignored by Git)
2. Copies the public key to the droplet and appends it to `/root/.ssh/authorized_keys`
3. Prints the path to the private key file for use in GitHub secrets

Finally, copy the **private** key contents from `.deploy-keys/gh-actions-rogainizer` into the `DROPLET_SSH_KEY` secret under **Settings → Secrets and variables → Actions**.

If you are using Gmail for SMTP, enable 2FA on the account, create an App Password (type "Mail", device "Other"), and paste that value into `SMTP_PASSWORD`. Use the Gmail address for `SMTP_USERNAME`.

## API routes

- `GET /` - API status message

Auth:

- `POST /api/auth/login`
- `GET /api/auth/validate`

Health:

- `GET /api/health` - checks API and DB connectivity

Users:

- `GET /api/users` - lists users
- `POST /api/users` - creates user (`{ "name": "...", "email": "..." }`)
- `PUT /api/users?name={originalName}&email={originalEmail}` - updates user key/data (`{ "name": "...", "email": "..." }`)
- `DELETE /api/users?name={name}&email={email}` - deletes user by key

JSON Loader:

- `GET /api/json-loader?url={http(s)-json-url}` - fetches JSON from remote URL

Events:

- `GET /api/events` - lists all events
- `GET /api/events/:eventId/results` - loads saved raw/scaled results for an event
- `POST /api/events/save-result` - saves/overwrites event details (**auth required**)
- `POST /api/events/:eventId/transformed-results` - saves transformed rows (**auth required**)
- `PUT /api/events/:eventId/results/:resultId` - updates a saved result row (**auth required**)
- `DELETE /api/events/:eventId/results/:resultId` - deletes a saved result row (**auth required**)

Leader Boards:

- `GET /api/leader-boards` - lists leader boards
- `POST /api/leader-boards` - creates a leader board
- `GET /api/leader-boards/year-results?year={year}` - lists events available for a year
- `GET /api/leader-boards/details/:leaderBoardId` - returns leader board + selected event ids
- `PUT /api/leader-boards/:leaderBoardId` - updates leader board details/event links (**auth required**)
- `GET /api/leader-boards/:leaderBoardId/scoreboard` - returns aggregated score table
- `GET /api/leader-boards/:leaderBoardId/member-events?member={name}` - member event breakdown

### cURL auth examples

Bash (Linux/macOS):

```bash
TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/login \
	-H "Content-Type: application/json" \
	-d '{"username":"admin","password":"admin"}' \
	| sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

curl -X PUT http://localhost:3000/api/events/1/results/1 \
	-H "Authorization: Bearer $TOKEN" \
	-H "Content-Type: application/json" \
	-d '{"team_name":"Example Team","team_member":"Alice Smith"}'
```

PowerShell:

```powershell
$login = Invoke-RestMethod -Method Post -Uri "http://localhost:3000/api/auth/login" -ContentType "application/json" -Body '{"username":"admin","password":"admin"}'
$token = $login.token

Invoke-RestMethod -Method Put -Uri "http://localhost:3000/api/events/1/results/1" -Headers @{ Authorization = "Bearer $token" } -ContentType "application/json" -Body '{"team_name":"Example Team","team_member":"Alice Smith"}'
```

Protected DELETE example (remove result row):

```bash
curl -X DELETE http://localhost:3000/api/events/1/results/1 \
	-H "Authorization: Bearer $TOKEN"
```

```powershell
Invoke-RestMethod -Method Delete -Uri "http://localhost:3000/api/events/1/results/1" -Headers @{ Authorization = "Bearer $token" }
```

Protected leader board update example:

```bash
curl -X PUT http://localhost:3000/api/leader-boards/1 \
	-H "Authorization: Bearer $TOKEN" \
	-H "Content-Type: application/json" \
	-d '{"name":"State Series","year":2026,"eventIds":[1,2,3]}'
```

```powershell
Invoke-RestMethod -Method Put -Uri "http://localhost:3000/api/leader-boards/1" -Headers @{ Authorization = "Bearer $token" } -ContentType "application/json" -Body '{"name":"State Series","year":2026,"eventIds":[1,2,3]}'
```
