# NauticNet

## Setup
```
asdf install

brew install netcdf-cxx

mix deps.get
mix compile # if exla fails, try it again (potential race condition)

docker-compose up
mix ecto.setup
```
