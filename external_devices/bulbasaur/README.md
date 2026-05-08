# Bulbasaur Devices

Bulbasaur-specific HyperBEAM devices live here so the core runtime can stay
close to upstream HyperBEAM. They are packaged with HyperBEAM's canonical
`rebar3 device` provider and loaded by name or spec ID at runtime.

## Devices

- `ao-payment@1.0`
- `arweave-byte-pricing@1.0`
- `bundler-settlement@1.0`
- `pricing-router@1.0`
- `process-ledger@1.0`
- `simple-oracle@1.0`

## Package And Verify

From the HyperBEAM checkout root:

```sh
rebar3 device package \
  --device-src external_devices/bulbasaur/src \
  --output-dir external_devices/bulbasaur/_build/devices

rebar3 device verify \
  --device-src external_devices/bulbasaur/src \
  --output-dir external_devices/bulbasaur/_build/devices
```

## Publish

Use a wallet that LapEE or another node trusts:

```sh
rebar3 device publish \
  --device-src external_devices/bulbasaur/src \
  --key /path/to/wallet.json
```

The command prints one spec ID and implementation ID per device. Runtime nodes
should set `load-remote-devices` to `true`, trust the publisher address in
`trusted-device-signers`, and resolve friendly device names with a
`name-resolvers` map such as:

```erlang
#{
    <<"name-resolvers">> => [
        #{
            <<"ao-payment@1.0">> => <<"SPEC_ID">>,
            <<"arweave-byte-pricing@1.0">> => <<"SPEC_ID">>,
            <<"bundler-settlement@1.0">> => <<"SPEC_ID">>,
            <<"pricing-router@1.0">> => <<"SPEC_ID">>,
            <<"process-ledger@1.0">> => <<"SPEC_ID">>,
            <<"simple-oracle@1.0">> => <<"SPEC_ID">>
        }
    ],
    <<"load-remote-devices">> => true,
    <<"trusted-device-signers">> => [<<"PUBLISHER_ADDRESS">>]
}.
```

The local `scripts/start-bulbasaur.sh` helper uses the same packaging API, writes
signed specs and implementations into the node's local store, and prepends this
alias map automatically for development.
