#!/usr/bin/env bash
# Shared configuration. The other scripts source this. Do not run it directly.
#
# Precedence: AGENT_MEMORY_VAULT env var, then the config file, then the default.

_am_config="${XDG_CONFIG_HOME:-$HOME/.config}/agent-memory/config"
# shellcheck disable=SC1090
[ -f "$_am_config" ] && . "$_am_config"

VAULT="${AGENT_MEMORY_VAULT:-${VAULT:-$HOME/agent-memory-vault}}"
