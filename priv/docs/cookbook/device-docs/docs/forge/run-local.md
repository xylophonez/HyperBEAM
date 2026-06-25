# Run Locally

Start a node with your packaged device in a fresh preloaded store:

```text
rebar3 device local
```

If port `8734` is already occupied, create a small config and choose another port:

```text
cat > device-test-8799.json <<'JSON'
{
  "port": 8799
}
JSON

HB_CONFIG=device-test-8799.json rebar3 device local
```

Test the `echo_lens` example device:

```text
curl -sS "http://localhost:8799/~echo-lens@1.0/echo?input=hello"
curl -sS "http://localhost:8799/~echo-lens@1.0/upper?input=hello"
```

Expected output:

```text
hello
HELLO
```
