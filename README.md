# NauticNet

## Setup

```sh
asdf install

npm install --prefix assets

mix deps.get
mix compile # if exla fails, try it again (potential race condition)

docker-compose up
mix ecto.setup
```

## DB Backup and Restore

### Backup

```sh
# Terminal A: set up a Fly tunnel to local port 5434
fly proxy 5434:5432 -a nautic-net-web-db-dev

# Terminal B: start Timescale on port 5433
docker-compose up

# Terminal C:
FLY_DB_PASSWORD='get-this-from-1password'
FLY_DB_PROXY_URL="postgresql://postgres:$FLY_DB_PASSWORD@localhost:5434/nautic_net_web_dev"
PATH="$PATH:/Applications/Postgres.app/Contents/Versions/15/bin/"
pg_dump --no-owner $FLY_DB_PROXY_URL > pg.dump
```

### Restore

```sh
# Terminal A: start Timescale on port 5433
docker-compose up

# Terminal B:
PATH="$PATH:/Applications/Postgres.app/Contents/Versions/15/bin/"
mix ecto.drop
mix ecto.create
psql postgres://postgres:postgres@localhost:5433/nautic_net_web_dev < pg.dump
```

## Debugging the Docker build

```sh
# To build the image locally
docker build .

# To build locally and debug a failing build step
DOCKER_BUILDKIT=0 docker build .
# and find the container ID of the last successful step, then do
docker run -it [container-id] bash
```

## Deploying to Fly

```sh
# Configuration
WEB_APP=nautic-net-web-dev
DB_APP=nautic-net-web-db-dev

# Create the web app
fly apps create $WEB_APP \
    --machines \
    --org dockyard-618

# Create the database app (copy credentials to 1Password, DockYard -> Engineering vault)
fly pg create \
    --name $DB_APP \
    --org dockyard-618 \
    --image-ref flyio/postgres-flex-timescaledb:15 \
    --region bos \
    --vm-size shared-cpu-1x \
    --initial-cluster-size 1 \
    --volume-size 10

# Get DB machine ID (requires jq; `brew install jq`)
DB_MACHINE_ID=$(fly machines list \
    --app $DB_APP \
    --json \
    | jq -r '.[0].id')

# Resize DB machine 256 MB -> 1 GB (PostGIS really needs the RAM!)
fly machine update $DB_MACHINE_ID \
    --app $DB_APP \
    --memory 1024 \
    --yes

# Create the database, role, and set DATABASE_URL on the web app
fly pg attach $DB_APP \
    --app $WEB_APP

# Set SECRET_KEY_BASE
fly secrets set \
    --stage \
    SECRET_KEY_BASE=`mix phx.gen.secret`

# Cross your fingers and toes...
fly deploy

# Allocate a static IPv4 address for UDP to work
fly ips allocate-v4
```

Answers for the prompts from `fly launch`:

```
Detected a Phoenix app
? Choose an app name (leaving blank will default to 'nautic-net-web-dev')
? App nautic-net-web-dev already exists, do you want to launch into that app? Yes
App will use 'bos' region as primary
Admin URL: https://fly.io/apps/nautic-net-web-dev
Hostname: nautic-net-web-dev.fly.dev
Set secrets on nautic-net-web-dev: SECRET_KEY_BASE
? Would you like to set up a Postgresql database now? No
? Would you like to set up an Upstash Redis database now? No
Preparing system for Elixir builds
Installing application dependencies
Running Docker release generator
Wrote config file fly.toml
? Would you like to deploy now? Yes
```
