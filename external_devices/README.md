# External Device Implementations

This directory holds device implementations that are intentionally not compiled
as part of the HyperBEAM application.

They are kept here as a local test fixture for Sam's device-loading-by-spec
flow. A node should reference the published device spec ID in its message or
configuration, then load a trusted implementation message tagged
`implements-device=<spec-id>`.

Use this directory to stage implementations for devices that are not part of the
core HyperBEAM application. Each implementation should have a corresponding
`Device-Spec` message and an implementation message tagged
`implements-device=<spec-id>` before it is loaded by a node.
