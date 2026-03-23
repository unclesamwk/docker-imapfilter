# docker-imapfilter

Hardened Docker image for running `imapfilter` as a scheduled worker.

Maintained by `unclesamwk`, inspired by and built from upstream `lefcha/imapfilter`.

## Highlights

- Multi-stage build.
- Runs as non-root user (`imap`).
- `tini` init process for clean signal handling.
- Exponential backoff on failed sync runs.
- Docker health check based on successful-run heartbeat.
- Secrets support via `*_FILE` environment variables.
- Configurable one-shot mode and schedule interval.

## Build

```bash
docker build -t anyone/imapfilter .
```

You can also choose a specific imapfilter ref:

```bash
docker build \
  --build-arg IMAPFILTER_REF=v2.8.2 \
  -t anyone/imapfilter .
```

For fully reproducible builds, pin an exact commit:

```bash
docker build \
  --build-arg IMAPFILTER_REF=master \
  --build-arg IMAPFILTER_COMMIT=<commit-sha> \
  -t anyone/imapfilter .
```

## Run (scheduled mode)

```bash
docker run -d \
  --name imapfilter \
  -e IMAP_SERVER=imap.example.com \
  -e IMAP_USER=alice@example.com \
  -e IMAP_PASS='super-secret' \
  -v "$(pwd)/config.lua:/home/imap/.imapfilter/config.lua:ro" \
  anyone/imapfilter
```

## Run once

```bash
docker run --rm \
  -e IMAPFILTER_ONCE=true \
  -e IMAP_SERVER=imap.example.com \
  -e IMAP_USER=alice@example.com \
  -e IMAP_PASS='super-secret' \
  -v "$(pwd)/config.lua:/home/imap/.imapfilter/config.lua:ro" \
  anyone/imapfilter
```

## Dry run (no-op)

Use imapfilter's `-n` flag to evaluate rules without applying changes:

```bash
docker run --rm \
  -e IMAPFILTER_ONCE=true \
  -e IMAPFILTER_EXTRA_ARGS="-n" \
  -e IMAP_SERVER=imap.example.com \
  -e IMAP_USER=alice@example.com \
  -e IMAP_PASS='super-secret' \
  -v "$(pwd)/config.lua:/home/imap/.imapfilter/config.lua:ro" \
  anyone/imapfilter
```

## Secrets via files

Instead of plain env vars, you can provide file-based secrets:

```bash
docker run --rm \
  -e IMAP_SERVER=imap.example.com \
  -e IMAP_USER=alice@example.com \
  -e IMAP_PASS_FILE=/run/secrets/imap_pass \
  -v "$(pwd)/config.lua:/home/imap/.imapfilter/config.lua:ro" \
  -v "$(pwd)/secrets/imap_pass:/run/secrets/imap_pass:ro" \
  anyone/imapfilter
```

## Runtime environment variables

- `IMAPFILTER_CONFIG` (default: `/home/imap/.imapfilter/config.lua`)
- `IMAPFILTER_INTERVAL_SECONDS` (default: `60`)
- `IMAPFILTER_ONCE` (`true` or `false`, default: `false`)
- `IMAPFILTER_EXTRA_ARGS` (optional extra `imapfilter` args)
- `IMAPFILTER_FAILURE_BACKOFF_SECONDS` (default: `15`)
- `IMAPFILTER_MAX_BACKOFF_SECONDS` (default: `300`)
- `IMAPFILTER_HEARTBEAT_FILE` (default: `/tmp/imapfilter.last_success_epoch`)
- `IMAPFILTER_HEALTH_MAX_AGE_SECONDS` (`0` means auto-calc from interval)

### Runtime variable behavior

- `IMAPFILTER_ONCE=true`: run one sync cycle and exit (no scheduling loop).
- `IMAPFILTER_ONCE=false`: run continuously, sleeping `IMAPFILTER_INTERVAL_SECONDS` between successful runs.
- `IMAPFILTER_EXTRA_ARGS`: passed directly to `imapfilter`.  
  Example: `IMAPFILTER_EXTRA_ARGS="-n"` enables dry-run/no-op mode.

## Imapfilter config input variables

The provided `config.lua` reads these variables (value or `*_FILE` variant):

- `IMAP_SERVER`
- `IMAP_USER`
- `IMAP_PASS`
- `IMAP_PORT` (optional, default `993`)
- `IMAP_SSL` (optional, default `ssl23`)

## Local developer commands

```bash
make lint
make build
make test
make run
make run-once
```

## CI

GitHub Actions runs on push and pull request and validates:

- shell syntax for runtime scripts
- Docker image build
- startup smoke test (fails correctly when config is missing)

## Docker Hub publish (amd64 + arm64)

The workflow [docker-publish.yml](/Users/swarkentin/GIT/private/docker-imapfilter/.github/workflows/docker-publish.yml) builds and pushes multi-arch images to Docker Hub for:

- pushes to `main`
- tags matching `v*`
- manual trigger (`workflow_dispatch`)

Set these repository secrets:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_PASSWORD` (Docker Hub password or access token)

Published image name:

- `${DOCKERHUB_USERNAME}/docker-imapfilter`
