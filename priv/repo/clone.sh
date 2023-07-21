#! /bin/bash

#
# Pulls down a database from Fly and restores it locally, wiping any existing local data.
#
# Establish a tunnel to the DB:
#
#     fly proxy 5434:5432 -a nautic-net-web-db-dev
#
# Set $FLY_DB_PROXY_URL:
#
#     export FLY_DB_PASSWORD='get-this-from-1password'
#     export FLY_DB_PROXY_URL="postgresql://postgres:$FLY_DB_PASSWORD@localhost:5434/nautic_net_web_dev"
#
# Start the local DB:
#
#    docker-compose up
#

set -e

if [ -z "$FLY_DB_PROXY_URL" ]; then
  echo '$FLY_DB_PROXY_URL must be set'
  exit 1
fi

which psql > /dev/null
if [ "$?" -ne 0 ]; then
  echo 'psql not found; is it in your $PATH?'
  exit 1
fi

which pg_dump > /dev/null
if [ "$?" -ne 0 ]; then
  echo 'pg_dump not found; is it in your $PATH?'
  exit 1
fi

echo '--> Recreating local database...'
mix ecto.drop
mix ecto.create

echo '--> Dumping remote database...'
pg_dump --no-owner "$FLY_DB_PROXY_URL" > pg.dump

echo '--> Restoring local database...'
psql 'postgres://postgres:postgres@localhost:5433/nautic_net_web_dev' < pg.dump