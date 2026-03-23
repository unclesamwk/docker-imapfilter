#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_PATH="${IMAPFILTER_CONFIG:-/home/imap/.imapfilter/config.lua}"
INTERVAL_SECONDS="${IMAPFILTER_INTERVAL_SECONDS:-60}"
RUN_ONCE="${IMAPFILTER_ONCE:-false}"
EXTRA_ARGS="${IMAPFILTER_EXTRA_ARGS:-}"
FAILURE_BACKOFF_SECONDS="${IMAPFILTER_FAILURE_BACKOFF_SECONDS:-15}"
MAX_BACKOFF_SECONDS="${IMAPFILTER_MAX_BACKOFF_SECONDS:-300}"
HEARTBEAT_FILE="${IMAPFILTER_HEARTBEAT_FILE:-/tmp/imapfilter.last_success_epoch}"

stop_requested="false"

on_term() {
  stop_requested="true"
  echo "[imapfilter] Stop requested, exiting after current run"
}

trap on_term TERM INT

resolve_secret_env() {
  local var_name="$1"
  local file_var_name="${var_name}_FILE"
  local var_value="${!var_name:-}"
  local file_var_value="${!file_var_name:-}"

  if [[ -n "${var_value}" && -n "${file_var_value}" ]]; then
    echo "[imapfilter] Both ${var_name} and ${file_var_name} are set; use only one" >&2
    exit 1
  fi

  if [[ -n "${file_var_value}" ]]; then
    if [[ ! -f "${file_var_value}" ]]; then
      echo "[imapfilter] ${file_var_name} points to missing file: ${file_var_value}" >&2
      exit 1
    fi
    export "${var_name}=$(<"${file_var_value}")"
  fi
}

resolve_secret_env "IMAP_SERVER"
resolve_secret_env "IMAP_USER"
resolve_secret_env "IMAP_PASS"
resolve_secret_env "IMAP_PORT"
resolve_secret_env "IMAP_SSL"

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "[imapfilter] Config not found: ${CONFIG_PATH}" >&2
  echo "[imapfilter] Mount it with: -v \"$HOME/.config/imapfilter:/home/imap/.imapfilter:ro\"" >&2
  exit 1
fi

if ! [[ "${INTERVAL_SECONDS}" =~ ^[0-9]+$ ]]; then
  echo "[imapfilter] IMAPFILTER_INTERVAL_SECONDS must be an integer, got: ${INTERVAL_SECONDS}" >&2
  exit 1
fi

if ! [[ "${FAILURE_BACKOFF_SECONDS}" =~ ^[0-9]+$ ]]; then
  echo "[imapfilter] IMAPFILTER_FAILURE_BACKOFF_SECONDS must be an integer, got: ${FAILURE_BACKOFF_SECONDS}" >&2
  exit 1
fi

if ! [[ "${MAX_BACKOFF_SECONDS}" =~ ^[0-9]+$ ]]; then
  echo "[imapfilter] IMAPFILTER_MAX_BACKOFF_SECONDS must be an integer, got: ${MAX_BACKOFF_SECONDS}" >&2
  exit 1
fi

run_imapfilter() {
  echo "[imapfilter] Starting run at $(date -Is)"
  # shellcheck disable=SC2086
  if imapfilter -c "${CONFIG_PATH}" ${EXTRA_ARGS}; then
    date +%s > "${HEARTBEAT_FILE}"
    echo "[imapfilter] Run finished successfully at $(date -Is)"
    return 0
  fi
  echo "[imapfilter] Run failed at $(date -Is)" >&2
  return 1
}

if [[ "${RUN_ONCE}" == "true" ]]; then
  run_imapfilter
  exit 0
fi

current_backoff="${FAILURE_BACKOFF_SECONDS}"
while true; do
  if run_imapfilter; then
    current_backoff="${FAILURE_BACKOFF_SECONDS}"
  else
    echo "[imapfilter] Sleeping ${current_backoff}s before retry" >&2
    sleep "${current_backoff}"
    if [[ "${current_backoff}" -lt "${MAX_BACKOFF_SECONDS}" ]]; then
      current_backoff=$((current_backoff * 2))
      if [[ "${current_backoff}" -gt "${MAX_BACKOFF_SECONDS}" ]]; then
        current_backoff="${MAX_BACKOFF_SECONDS}"
      fi
    fi
    continue
  fi

  if [[ "${stop_requested}" == "true" ]]; then
    echo "[imapfilter] Exiting cleanly"
    exit 0
  fi

  sleep "${INTERVAL_SECONDS}"
done
