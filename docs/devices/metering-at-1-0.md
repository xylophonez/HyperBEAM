# Device: ~metering@1.0

## Overview

The `~metering@1.0` device is a P4 pricing-device implementation for dynamic
resource usage. It can estimate a request, collect resource usage during request
handling, and return a final price from configured per-resource rates.

## Device Spec Message

```erlang
#{
    <<"data-protocol">> => <<"ao">>,
    <<"type">> => <<"Device-Spec">>,
    <<"name">> => <<"metering@1.0">>
}
```

## Exports

* `estimate`
* `price`
* `quote`
* `consume`

## Configuration

The node message or base message may provide:

* `metering-rates`: map of normalized resource name to integer price per unit.

Common resources include:

* `arweave-bytes`
* `beam-reductions`

## `quote`

Prices a resource amount directly.

```erlang
#{
    <<"path">> => <<"quote">>,
    <<"resource">> => <<"arweave-bytes">>,
    <<"amount">> => 1000
}
```

The response is the integer price.

## `consume`

Adds resource usage to the current process-local metering session. Calls outside
an active session are no-ops.

```erlang
#{
    <<"path">> => <<"consume">>,
    <<"resource">> => <<"arweave-bytes">>,
    <<"amount">> => 1000
}
```

## Security Notes

This device only calculates prices. A payment gate such as `p4@1.0` and a ledger
device are responsible for enforcing balances and applying charges.
