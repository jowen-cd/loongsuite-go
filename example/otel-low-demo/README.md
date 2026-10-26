# otel-low-demo

gin demo pinned to a **low** OpenTelemetry version (v1.31.0), below the
agent's GLS minimum (v1.39.0). It exists to verify the whitelist floor
behavior of this fork:

- Building with `otel-fork` raises the resolved otel version to the floor
  (the max otel require across the whitelisted rule modules), because the
  GLS hooks can only be injected into `otel/sdk` >= v1.39.0.
- `scripts/sync_upstream.sh` builds this demo on every upstream sync and
  asserts the resolved version is >= v1.39.0, warning when it rises above
  the v1.40.0 floor discipline.

Build:

```bash
../../otel-fork go build -o demo .
```
