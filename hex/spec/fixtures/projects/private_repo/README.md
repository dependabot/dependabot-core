# Dependabot

Private hex repo built for testing dependabot.

## Usage

Build and run the app locally:

```bash
MIX_ENV=prod mix do deps.get, release

_build/prod/rel/dependabot/bin/dependabot start
```

Run the app within the docker container locally:

```bash
docker build -t dependabot/private .
docker run --env PORT=8000 -p 8000:8000 dependabot/private
```

Or, deploy to fly by changing the name in `fly.toml` and then run:

```bash
fly launch
```
