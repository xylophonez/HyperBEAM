# External Device Implementations

This directory holds device implementations that are intentionally not compiled
as part of the HyperBEAM application.

They are kept here as a local test fixture for Sam's device-loading-by-spec
flow. A node should reference the published device spec ID in its message or
configuration, then load a trusted implementation message tagged
`implements-device=<spec-id>`.

The representative eunit test in `hb_ao_test_vectors` compiles
`dev_metering.erl` from this directory, writes a local `Device-Spec` message and
an implementation message, then resolves the device by the spec ID through the
gateway client path.
