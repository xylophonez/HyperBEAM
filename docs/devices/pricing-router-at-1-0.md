# Device: ~pricing-router@1.0

## Overview

The `~pricing-router@1.0` device is a P4 pricing-device adapter. It selects a
pricing device based on the request being priced, then forwards the P4 pricing
call to that device.

It allows a node to keep a default pricing policy for most routes while sending
specific routes, such as bundler uploads, to canonical `metering@1.0`.

## Device Spec Message

```erlang
#{
    <<"data-protocol">> => <<"ao">>,
    <<"type">> => <<"Device-Spec">>,
    <<"name">> => <<"pricing-router@1.0">>
}
```

## Exports

* `estimate`
* `price`

These match the P4 pricing-device interface.

## Configuration

The base message or node message may provide:

* `pricing-routes`: list of router-style route entries.
* `default-pricing-device`: pricing device used when no route matches. Defaults
  to `simple-pay@1.0`.

Each route may include:

* `template`: request path template to match.
* `pricing-device`: pricing device used for matching requests.
* additional keys to merge into the forwarded pricing base message.

## Route Selection

P4 calls pricing devices with a request that contains the original user request
under the `request` key. `pricing-router@1.0` matches that nested request against
`pricing-routes` using the standard router matching semantics.

If a route matches, the route's `pricing-device` is selected. If no route
matches, `default-pricing-device` is selected.

## `estimate`

Forwards an `estimate` call to the selected pricing device.

### Request

```erlang
#{
    <<"path">> => <<"estimate">>,
    <<"request">> => OriginalUserRequest
}
```

### Forwarded Request

```erlang
OriginalPricingReq#{ <<"path">> => <<"estimate">> }
```

The forwarded base message is the pricing-router base merged with the matching
route, with `template` removed and `device` set to the selected pricing device.

## `price`

Forwards a `price` call to the selected pricing device.

### Request

```erlang
#{
    <<"path">> => <<"price">>,
    <<"request">> => OriginalUserRequest
}
```

The forwarded message shape follows the same rule as `estimate`, with
`path=price`.

## Example

```erlang
#{
    <<"device">> => <<"pricing-router@1.0">>,
    <<"default-pricing-device">> => <<"simple-pay@1.0">>,
    <<"pricing-routes">> => [
        #{
            <<"template">> => <<"/~bundler@1.0/tx">>,
            <<"pricing-device">> => <<"metering@1.0">>
        }
    ]
}
```

With this configuration, P4 uses `metering@1.0` to price bundler uploads and
`simple-pay@1.0` for other protected routes.

## Security Notes

This device does not calculate prices itself. Its correctness depends on route
matching and the selected pricing devices. Operators should keep route templates
specific enough that protected routes cannot accidentally fall through to an
unpriced or lower-priced default.
