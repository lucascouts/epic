# EARS Notation Reference

EARS (Easy Approach to Requirements Syntax) provides structured patterns for writing unambiguous, testable requirements.

## Keywords

### WHEN (Event-Driven)

Triggered by a discrete event.

```
WHEN <event/trigger> THE SYSTEM SHALL <response>
```

Example:
```
WHEN a user submits a registration form with valid data THE SYSTEM SHALL create a new user account and return a confirmation message
```

### WHILE (State-Driven)

Continuous behavior during a state.

```
WHILE <state/condition is active> THE SYSTEM SHALL <ongoing behavior>
```

Example:
```
WHILE a flow execution is in RUNNING status THE SYSTEM SHALL update the execution heartbeat every 30 seconds
```

### IF (Conditional)

Behavior depends on a condition being true.

```
IF <condition is true> THEN THE SYSTEM SHALL <response>
```

Example:
```
IF the retry count exceeds the configured maximum THEN THE SYSTEM SHALL mark the execution step as FAILED and capture a screenshot
```

### WHERE (Context-Specific)

Behavior applies in a specific context or location.

```
WHERE <context/location> THE SYSTEM SHALL <context-specific behavior>
```

Example:
```
WHERE a credential is accessed during script execution THE SYSTEM SHALL log the access event to the audit trail
```

### Ubiquitous (Always True)

No condition — behavior always applies.

```
THE SYSTEM SHALL <behavior>
```

Example:
```
THE SYSTEM SHALL encrypt all credential values using AES-256-GCM before storing them in the database
```

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| Using `SHOULD` | Ambiguous — implies optional | Always use `SHALL` |
| Compound conditions | `WHEN A AND B AND C` is untestable as one unit | Split into separate requirements |
| Implementation details | `SHALL use Redis to store...` couples to implementation | `SHALL persist job state across restarts` |
| Internal mechanism as behavior | `SHALL store the record in a B-tree index` describes an internal mechanism invisible to the actor | Describe what the actor observes: `SHALL persist the record and make it retrievable by ID` |
| Vague behavior | `SHALL handle errors appropriately` | `SHALL return HTTP 429 with Retry-After header` |
| Untestable criteria | `SHALL be fast` | `SHALL respond within 200ms for 95th percentile` |
| Negative requirements | `SHALL NOT crash` | State positive: `SHALL return error response with status 500` |

## Combining Keywords

Requirements can combine keywords when needed:

```
WHILE the system is in maintenance mode, IF a user attempts to execute a flow, THEN THE SYSTEM SHALL queue the execution and notify the user of the expected delay
```

Keep combinations to 2 keywords maximum. If more complex, split into separate requirements.
