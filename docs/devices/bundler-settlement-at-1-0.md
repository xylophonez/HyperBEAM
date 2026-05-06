# Device: ~bundler-settlement@1.0

## Overview

The `~bundler-settlement@1.0` device is a bundler completion hook that settles
paid bundle work after the bundler reports successful completion.

In the paid bundler flow, P4 charges the uploader when the bundler upload request
is accepted. The charged amount is credited to a local ledger account controlled
by the node. The settlement hook runs after a bundled message or bundle completes
and moves the metered fee from that settlement account to the configured
beneficiary account.

This device is intentionally small. It delegates pricing to a pricing device and
balance mutation to a ledger device.

## Device Spec Message

```erlang
#{
    <<"data-protocol">> => <<"ao">>,
    <<"type">> => <<"Device-Spec">>,
    <<"name">> => <<"bundler-settlement@1.0">>
}
```

## Exports

* `bundled-message-complete`
* `bundle-complete`

Both exports perform the same settlement operation. Operators may install either
hook depending on whether they want to settle once per item or once per completed
bundle.

## Configuration

The hook base message accepts:

* `pricing-device`: pricing device used to quote the completed resource amount.
  Defaults to canonical `metering@1.0`.
* `ledger-device`: P4-compatible ledger device used to charge the settlement
  account.
* `settlement-account`: account debited during settlement. Defaults to
  `p4-recipient`, then `operator`.
* `beneficiary`: account credited during settlement. Defaults to
  `bundler-beneficiary`, then `operator`.
* `hook`: optional `hook@1.0` configuration, commonly
  `#{ <<"result">> => <<"ignore">> }` so settlement failures do not replace the
  bundler response body.

The request supplied by the bundler hook must contain:

* `bundled-size`: size, in bytes, of the completed item or bundle.
* `body`: completed item or bundle transaction.

## Settlement Flow

For a completed request with `bundled-size = Size`, the device:

1. Calls the configured pricing device:

   ```erlang
   #{
       <<"path">> => <<"quote">>,
       <<"resource">> => <<"arweave-bytes">>,
       <<"amount">> => Size
   }
   ```

2. If the quote is zero, returns `{ok, Req}` without mutating balances.
3. Otherwise signs and sends a ledger charge:

   ```erlang
   #{
       <<"path">> => <<"charge">>,
       <<"quantity">> => Amount,
       <<"account">> => SettlementAccount,
       <<"recipient">> => Beneficiary,
       <<"request">> => CompletionRequest
   }
   ```

4. If the ledger charge succeeds, returns `{ok, Req}`.

## Response

On successful settlement:

```erlang
{ok, Req}
```

On failure, the error from the pricing or ledger device is returned.

## Security Notes

This device does not prove Arweave finality by itself. It relies on the bundler's
completion hook semantics. Operators should only attach it to hooks that fire
after the bundler has reached the desired success condition.

The ledger device is responsible for enforcing account authorization and
preventing unauthorized settlement-account debits.
