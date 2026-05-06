# Device: ~ao-payment@1.0

## Overview

The `~ao-payment@1.0` device imports a verified AO token transfer from an AO
mainnet token process into a local HyperBEAM process-backed ledger.

It is intended for nodes that accept AO payments into a node-controlled deposit
address, then credit the payer on a local ledger after the AO token process has
emitted matching `Debit-Notice` and `Credit-Notice` messages.

This device does not initiate the original AO transfer. It verifies an already
scheduled AO token transfer and, on import, schedules a local `Credit-Notice`
into the configured ledger process.

## Device Spec Message

```erlang
#{
    <<"data-protocol">> => <<"ao">>,
    <<"type">> => <<"Device-Spec">>,
    <<"name">> => <<"ao-payment@1.0">>
}
```

## Exports

* `verify`
* `ingest`

## Configuration

The device reads the following values from the request or node message:

* `token`: AO token process ID.
* `ledger`: local process-backed ledger ID to credit.
* `deposit-address`: address that must receive the AO token transfer. Defaults
  to the configured ledger ID if absent.
* `message-id`: AO transfer message ID. The request key `id` may be used as a
  fallback.
* `slot`: AO token process schedule slot containing the transfer.
* `sender`: account expected to have sent the AO transfer.
* `quantity`: token quantity, in the token's smallest units.
* `recipient`: optional local ledger account to credit. If omitted, the sender is
  credited.

The node message may provide these defaults:

* `ao-payment-token`
* `ao-payment-ledger`
* `ao-payment-deposit-address`
* `ao-payment-mainnet-url`
* `ao-payment-node`
* `ao-payment-imports`

## `verify`

`verify` checks AO mainnet state for the requested transfer.

The implementation must verify that:

1. The token process schedule at `slot` includes the expected `Transfer`
   assignment.
2. The transfer message has `Action=Transfer`.
3. The transfer message recipient matches `deposit-address`.
4. The transfer message quantity matches `quantity`.
5. The token process result for that slot contains a matching `Debit-Notice`
   targeting `sender`.
6. The token process result for that slot contains a matching `Credit-Notice`
   targeting `deposit-address`.

If the AO credit notice contains `X-HB-Recipient`, that value is used as the
local ledger recipient. Otherwise the original `sender` is used.

### Request

```erlang
#{
    <<"path">> => <<"verify">>,
    <<"token">> => TokenProcessID,
    <<"ledger">> => LocalLedgerID,
    <<"deposit-address">> => NodeDepositAddress,
    <<"message-id">> => TransferMessageID,
    <<"slot">> => Slot,
    <<"sender">> => SenderAddress,
    <<"quantity">> => Quantity,
    <<"recipient">> => OptionalLocalRecipient
}
```

### Response

On success:

```erlang
{ok, #{
    <<"token">> => TokenProcessID,
    <<"message-id">> => TransferMessageID,
    <<"ledger">> => LocalLedgerID,
    <<"sender">> => SenderAddress,
    <<"recipient">> => LocalRecipient,
    <<"quantity">> => Quantity,
    <<"notice-reference">> => NoticeReference
}}
```

On failure the device returns `{error, ErrorMessage}`. Error messages should
include an HTTP-style `status` key when the error is user-facing.

## `ingest`

`ingest` performs `verify` and, if verification succeeds, imports the payment
into the local ledger. Imports are idempotent by `(token, message-id)`.

On first import, the device schedules a local ledger message:

```erlang
#{
    <<"target">> => LocalLedgerID,
    <<"type">> => <<"Message">>,
    <<"action">> => <<"Credit-Notice">>,
    <<"from-process">> => TokenProcessID,
    <<"recipient">> => LocalRecipient,
    <<"quantity">> => Quantity,
    <<"sender">> => SenderAddress,
    <<"ao-payment-id">> => TransferMessageID
}
```

On repeated import, it returns the previously imported payment with
`status=already-imported`.

## Security Notes

The device assumes the configured AO mainnet endpoint returns canonical schedule
and compute results for the token process. Operators should use a trusted
HyperBEAM or AO gateway endpoint.

The node wallet signs the local ledger credit notice. The local ledger process
must separately enforce that only authorized node/operator messages can mint or
credit local balances.
