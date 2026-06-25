# Create A Process-Shaped Message

A process is a device composition: scheduler, execution device, push behavior, and state. This recipe builds a process-shaped message and shows which node settings must exist before scheduling or compute can run.

## Build A Process Definition Shape

```bash
curl -sS "http://localhost:8734/~message@1.0&device=process%401.0&scheduler=scheduler%401.0&execution-device=lua%405.3a&push-device=push%401.0/format~hyperbuddy@1.0"
```

## Check Process Infrastructure

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/format~hyperbuddy@1.0" | grep -i -E 'process|scheduler|execution|compute|push|lua|wasm|stack'
curl -sS "http://localhost:8734/~process@1.0/info/format~hyperbuddy@1.0"
curl -sS "http://localhost:8734/~scheduler@1.0/info/format~hyperbuddy@1.0"
```

## Try A Slot Read

```bash
curl -sS "http://localhost:8734/~process@1.0/slot&slot=0/format~hyperbuddy@1.0"
```

A real slot result requires a process base message and scheduler state. Without those, the response usefully tells you which input is missing.

## How It Composes

| Device | Role |
|---|---|
| `~process@1.0` | Routes process operations. |
| `~scheduler@1.0` | Stores and returns assignments/slots. |
| `~lua@5.3a` or `~wasm-64@1.0` | Executes process logic. |
| `~patch@1.0` | Shapes assignment/input/output paths. |
| `~push@1.0` | Pushes produced messages onward. |
