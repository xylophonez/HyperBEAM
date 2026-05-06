# Device: ~process-ledger@1.0

## Overview

The `~process-ledger@1.0` device is a P4 ledger-device adapter for an AO-Core
`process@1.0` token ledger.

It lets P4 read balances from a configured ledger process and apply charges by
pushing signed charge messages to that process. The ledger process remains
responsible for enforcing authorization and balance rules.

## Device Spec Message

```erlang
#{
    <<"data-protocol">> => <<"ao">>,
    <<"type">> => <<"Device-Spec">>,
    <<"name">> => <<"process-ledger@1.0">>
}
```

## Exports

* `balance`
* `charge`

These match the P4 ledger-device interface.

## Configuration

The base message must provide:

* `ledger-path`: route to the ledger process, for example
  `/<LedgerID>~process@1.0`.

The node message must provide whatever wallet and authority configuration is
required to sign messages that the target ledger process will accept.

## `balance`

Reads the target account balance from the configured ledger process.

### Target Selection

The balance target is selected in this order:

1. `target` from the balance request.
2. `target` from a nested `request`.
3. First signer of the balance request.
4. First signer of a nested `request`.

If no target can be found, the balance is treated as zero.

### Ledger Query

For target `Account`, the device resolves:

```text
<ledger-path>/now/balance/<Account>
```

### Response

On success:

```erlang
{ok, Balance}
```

If the ledger path is missing:

```erlang
{error, #{ <<"status">> => 500, <<"body">> => <<"Missing process ledger path.">> }}
```

If the ledger cannot return a balance for the account, the device returns
`{ok, 0}`.

## `charge`

Applies a P4 charge by pushing the signed charge request to the configured
ledger process.

### Request

```erlang
#{
    <<"path">> => <<"charge">>,
    <<"quantity">> => Quantity,
    <<"account">> => AccountToDebit,
    <<"recipient">> => AccountToCredit,
    <<"request">> => OriginalPaidRequest
}
```

### Ledger Push

The device forwards the charge request to:

```text
(<ledger-path>)/push
```

using:

```erlang
#{
    <<"path">> => <<"(<ledger-path>)/push">>,
    <<"method">> => <<"POST">>,
    <<"body">> => ChargeRequest
}
```

### Response

The response is the result of the ledger process push. If `ledger-path` is
missing, the device returns a `500` error message.

## Security Notes

The ledger process, not this adapter, is the authority for balance mutation. A
production ledger should reject unsigned or unauthorized charge messages and
should enforce insufficient-balance behavior.

Operators should configure `ledger-path` explicitly. If this device is loaded as
a remote device implementation, configuration should reference its published
device spec ID rather than relying on it being preloaded by name.
