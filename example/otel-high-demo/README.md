# otel-high-demo

gin demo pinned to the **latest** OpenTelemetry version, above the agent's
whitelist floor. It verifies the "user version wins" contract of this fork:

- Building with `otel-fork` must leave the user's otel version untouched
  (no forced upgrade, no pinning).
- `scripts/sync_upstream.sh` builds this demo on every upstream sync, keeps
  the pin fresh (bumping it to the latest otel release whenever the tool
  floor catches up, per the rule "the demo must stay above the tool floor
  unless the tool is already at the latest release"), and asserts the
  resolved version equals the pin.

Build:

```bash
../../otel-fork go build -o demo .
```
