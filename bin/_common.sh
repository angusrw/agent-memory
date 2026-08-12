#!/usr/bin/env bash
# Shared configuration resolution. Sourced by the other scripts, never run directly.
#
# Precedence: AGENT_MEMORY_VAULT env var -> config file -> default.

_am_config="${XDG_CONFIG_HOME:-$HOME/.config}/agent-memory/config"
# shellcheck disable=SC1090
[ -f "$_am_config" ] && . "$_am_config"

VAULT="${AGENT_MEMORY_VAULT:-${VAULT:-$HOME/agent-memory-vault}}"
