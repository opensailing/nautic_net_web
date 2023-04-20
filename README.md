# NauticNet

## Setup

```sh
asdf install

brew install netcdf-cxx

npm install --prefix assets

mix deps.get
mix compile # if exla fails, try it again (potential race condition)

docker-compose up
mix ecto.setup
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
