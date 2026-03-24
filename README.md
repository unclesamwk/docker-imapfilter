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
  -v "$HOME/.config/imapfilter:/home/imap/.imapfilter:ro" \
  anyone/imapfilter
```

## Run once

```bash
docker run --rm \
  -e IMAPFILTER_ONCE=true \
  -e IMAP_SERVER=imap.example.com \
  -e IMAP_USER=alice@example.com \
  -e IMAP_PASS='super-secret' \
  -v "$HOME/.config/imapfilter:/home/imap/.imapfilter:ro" \
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
  -v "$HOME/.config/imapfilter:/home/imap/.imapfilter:ro" \
  anyone/imapfilter
```

## Secrets via files

Instead of plain env vars, you can provide file-based secrets:

```bash
docker run --rm \
  -e IMAP_SERVER=imap.example.com \
  -e IMAP_USER=alice@example.com \
  -e IMAP_PASS_FILE=/run/secrets/imap_pass \
  -v "$HOME/.config/imapfilter:/home/imap/.imapfilter:ro" \
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

### Single-account env model

- This image expects one IMAP account per container run.
- Use one set of account variables: `IMAP_SERVER`, `IMAP_USER`, `IMAP_PASS` (plus optional `IMAP_PORT`, `IMAP_SSL`).
- Wildcard or indexed env variables like `IMAP_USER*` are not supported by default.
- For multiple accounts, run multiple containers (each with its own env file) or implement custom multi-account logic in `config.lua`.

## Imapfilter config input variables

The provided `config.lua` reads these variables (value or `*_FILE` variant):

- `IMAP_SERVER`
- `IMAP_USER`
- `IMAP_PASS`
- `IMAP_PORT` (optional, default `993`)
- `IMAP_SSL` (optional, default `auto`)

## What is possible with imapfilter?

Common operations include:

- move messages between folders
- copy messages to other folders/accounts
- delete messages
- set/unset flags (seen, flagged, etc.)
- filter by sender, subject, header, body, age, size, read/unread, recent
- combine filters with `*` (AND), `+` (OR), `-` (EXCEPT)

### Rule examples (Lua)

```lua
-- Base account from env vars (as in this repository)
account = IMAP {
  server = os.getenv('IMAP_SERVER'),
  username = os.getenv('IMAP_USER'),
  password = os.getenv('IMAP_PASS'),
  port = tonumber(os.getenv('IMAP_PORT') or '993'),
  ssl = os.getenv('IMAP_SSL') or 'auto',
}

-- 1) Move unread newsletters into "Newsletters"
pcall(function() account:create_mailbox('Newsletters') end)
local newsletters = account.INBOX:is_unseen() *
  account.INBOX:contain_from('newsletter@example.com')
newsletters:move_messages(account.Newsletters)

-- 2) Delete obvious spam by subject
local spam = account.INBOX:contain_subject('[SPAM]')
spam:delete_messages()

-- 3) Mark important mails as flagged
local important = account.INBOX:contain_from('boss@example.com') +
  account.INBOX:contain_subject('urgent')
important:mark_flagged()

-- 4) Archive old notifications (>30 days)
pcall(function() account:create_mailbox('Archive') end)
local old_notifications = account.INBOX:contain_from('no-reply@example.com') *
  account.INBOX:is_older(30)
old_notifications:move_messages(account.Archive)

-- 5) Complex filter: unread from A or B, but not matching body pattern
local filtered = (
  account.INBOX:is_unseen() *
  (account.INBOX:contain_from('a@example.com') +
   account.INBOX:contain_from('b@example.com'))
) - account.INBOX:match_body('.*ignore-this-pattern.*')
filtered:mark_seen()
```

### Dry-run first (recommended)

Test rules safely without applying changes:

```bash
docker run --rm \
  --env-file "$HOME/.config/imapfilter/.env" \
  -e IMAPFILTER_ONCE=true \
  -e IMAPFILTER_EXTRA_ARGS="-n" \
  -v "$HOME/.config/imapfilter:/home/imap/.imapfilter:ro" \
  anyone/imapfilter
```

Official references:

- `imapfilter_config(5)`: https://raw.githubusercontent.com/lefcha/imapfilter/master/doc/imapfilter_config.5
- sample config: https://raw.githubusercontent.com/lefcha/imapfilter/master/samples/config.lua

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

Docker Hub profile text files in this repository:

- short description: [.dockerhub-description.txt](/Users/swarkentin/GIT/private/docker-imapfilter/.dockerhub-description.txt)
- full Docker Hub README: [DOCKERHUB.md](/Users/swarkentin/GIT/private/docker-imapfilter/DOCKERHUB.md)
