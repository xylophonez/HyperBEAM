#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
rebar3 device verify \
    --device-src external_devices/bulbasaur/src \
    --output-dir external_devices/bulbasaur/_build/devices
exec rebar3 shell --apps hackney --eval 'file:script("scripts/start-bulbasaur.erl").'
