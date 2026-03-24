# docker-imapfilter

Container image for running `imapfilter` as a scheduled mail filtering worker.

## Highlights

- Multi-arch image (`linux/amd64`, `linux/arm64`)
- Non-root runtime user (`imap`)
- `tini` init for clean signal handling
- Optional one-shot mode (`IMAPFILTER_ONCE=true`)
- Dry-run support (`IMAPFILTER_EXTRA_ARGS="-n"`)
- Secret file support (`*_FILE` variables)
- Healthcheck with successful-run heartbeat
- Exponential backoff on failures

## Quick Start

```bash
docker run -d \
  --name imapfilter \
  --env-file "$HOME/.config/imapfilter/.env" \
  -v "$HOME/.config/imapfilter:/home/imap/.imapfilter:ro" \
  unclesamwk/docker-imapfilter:latest
```

Example `.env`:

```dotenv
IMAP_SERVER=imap.example.com
IMAP_USER=alice@example.com
IMAP_PASS=super-secret
IMAP_PORT=993
IMAP_SSL=auto
```

## Dry Run (No Changes)

```bash
docker run --rm \
  --env-file "$HOME/.config/imapfilter/.env" \
  -e IMAPFILTER_ONCE=true \
  -e IMAPFILTER_EXTRA_ARGS="-n" \
  -v "$HOME/.config/imapfilter:/home/imap/.imapfilter:ro" \
  unclesamwk/docker-imapfilter:latest
```

## Runtime Variables

- `IMAPFILTER_CONFIG` (default: `/home/imap/.imapfilter/config.lua`)
- `IMAPFILTER_INTERVAL_SECONDS` (default: `60`)
- `IMAPFILTER_ONCE` (`true` or `false`, default: `false`)
- `IMAPFILTER_EXTRA_ARGS` (pass-through args for `imapfilter`)
- `IMAPFILTER_FAILURE_BACKOFF_SECONDS` (default: `15`)
- `IMAPFILTER_MAX_BACKOFF_SECONDS` (default: `300`)
- `IMAPFILTER_HEARTBEAT_FILE` (default: `/tmp/imapfilter.last_success_epoch`)
- `IMAPFILTER_HEALTH_MAX_AGE_SECONDS` (`0` = auto)

## Account Variables (single-account model)

- `IMAP_SERVER`
- `IMAP_USER`
- `IMAP_PASS`
- `IMAP_PORT` (optional, default `993`)
- `IMAP_SSL` (optional, default `auto`)

`*_FILE` variants are supported (for example `IMAP_PASS_FILE`).

## Tags

- `latest`
- `v*` release tags from this repository

## Source

- GitHub: https://github.com/unclesamwk/docker-imapfilter
- Upstream inspiration: https://github.com/lefcha/imapfilter
