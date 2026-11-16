# Roblox playtest charter

## Session metadata

- **Date/time:**
- **Place/universe and build/version:**
- **Studio mode and DataModels:**
- **Tester profile:** first-time / returning / expert / synthetic agent
- **Party size and client count:**
- **Device, viewport, orientation, and input:**
- **Profile/test-data state:**

## Test decision

- **Question or acceptance criterion:**
- **Systems in scope:**
- **Out of scope:**
- **Known risks or blockers:**
- **Stop conditions:**

## Preconditions

List exact starting state, required feature flags/config, spawn/location, inventory/currency, permissions, and network assumptions. Use synthetic or test-owned data.

## Case matrix

| ID | Type | Preconditions | Steps | Expected observable result | Evidence | Result |
| --- | --- | --- | --- | --- | --- | --- |

Use result values `PASS`, `FAIL`, `BLOCKED`, and `NOT RUN`.

Recommended case types:

- critical happy path;
- first-time comprehension;
- boundary/min/max/empty state;
- invalid or duplicate action;
- cancel/interruption;
- death/reset/respawn;
- disconnect/rejoin/late join;
- two-player concurrency or contention;
- persistence round trip;
- prior-bug regression;
- representative device/input;
- degraded/failure dependency.

Only include types relevant to the feature.

## Exploratory observations

| Timestamp/step | Player action | Observed response | Interpretation | Follow-up |
| --- | --- | --- | --- | --- |

Keep interpretation separate from observation.

## Result summary

| Category | Total | Pass | Fail | Blocked | Not run |
| --- | --- | --- | --- | --- | --- |

- **Critical path verdict:**
- **Environment limitations:**
- **Top findings:**
- **Highest-value next test:**
- **Cleanup completed:**
