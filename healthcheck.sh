#!/usr/bin/env bash
set -Eeuo pipefail

heartbeat_file="${IMAPFILTER_HEARTBEAT_FILE:-/tmp/imapfilter.last_success_epoch}"
max_age="${IMAPFILTER_HEALTH_MAX_AGE_SECONDS:-0}"
interval="${IMAPFILTER_INTERVAL_SECONDS:-60}"

if ! [[ "${interval}" =~ ^[0-9]+$ ]]; then
  echo "[healthcheck] IMAPFILTER_INTERVAL_SECONDS is not an integer: ${interval}" >&2
  exit 1
fi

if ! [[ "${max_age}" =~ ^[0-9]+$ ]]; then
  echo "[healthcheck] IMAPFILTER_HEALTH_MAX_AGE_SECONDS is not an integer: ${max_age}" >&2
  exit 1
fi

if [[ "${max_age}" -eq 0 ]]; then
  max_age=$((interval * 3 + 30))
fi

if [[ ! -s "${heartbeat_file}" ]]; then
  echo "[healthcheck] Heartbeat file missing: ${heartbeat_file}" >&2
  exit 1
fi

last_success_epoch="$(<"${heartbeat_file}")"
if ! [[ "${last_success_epoch}" =~ ^[0-9]+$ ]]; then
  echo "[healthcheck] Invalid heartbeat value in ${heartbeat_file}: ${last_success_epoch}" >&2
  exit 1
fi

now_epoch="$(date +%s)"
age=$((now_epoch - last_success_epoch))

if [[ "${age}" -gt "${max_age}" ]]; then
  echo "[healthcheck] Last successful run is too old (${age}s > ${max_age}s)" >&2
  exit 1
fi

exit 0
