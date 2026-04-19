# Self-Review Checklist

Shared checklist applied before writing each phase artifact to disk.

## Inline Review (all scales)

Before writing each phase artifact to disk, silently ask yourself:

1. **Inputs covered?** Every user input has a validation rule or explicit "no validation" decision
2. **Ownership clear?** Every entity has clear ownership semantics
3. **Error paths?** Every happy path has a corresponding error/failure path
4. **State transitions?** For every "user does X", what happens if already in state X?
5. **Consistency?** Every entity in story.md appears in design.md, every requirement in tasks.md
6. **Scope leaks?** Nothing added that the user didn't request or confirm
7. **Parameters concrete?** Every numeric limit, threshold, page size, timeout, or retry count referenced in requirements has an explicit value — either in the requirement itself or in Constraints
8. **Open decisions resolved?** Every "or" / "alternatively" / "either X or Y" in design.md is resolved to a single approach in tasks.md — tasks must not inherit ambiguity from design
9. **Interface contracts satisfied?** (Phase 2+3) Every data boundary between components has matching shapes on both sides. When component A produces output consumed by component B, the data structure A sends must contain every field B expects. This applies to any producer→consumer relationship: handler→template/view, API→client, service→controller, parent→child component, event emitter→listener. For each interface defined in design.md, trace the data shape from producer to consumer and verify completeness.
10. **Error propagation complete?** (Phase 3) Every operation in a ToDo field that can fail must have explicit error handling **OR** a documented reason why the framework handles it. In languages/frameworks where input parsing is automatic (Django, Spring Boot, FastAPI, Express with middleware), framework-handled errors are acceptable without explicit mention. In languages/frameworks where it's manual (Go net/http, Rust actix-web, plain Node.js), the ToDo must say "parse input **and handle error**". This applies to ALL function calls that return errors — not just store/service methods but also stdlib functions like form parsing, type conversions, and file operations. The rule: **no silent failure at system boundaries**. When writing ToDo fields, use "call X and handle error" rather than just "call X".
11. **Testing strategy covered?** (Phase 3 only) Every testing level defined in design.md's Testing Strategy has at least one corresponding task with a Tests field. If a level is missing, flag it — do not silently drop it.
12. **Literal fidelity?** Re-read each requirement as a checklist of **behaviors**, not a single action. "Do A with B displaying C" is three checks: (1) does A, (2) with B, (3) displaying C. Every qualifier, prepositional phrase, and conjunction in the requirement is a separate verification point. If a task ToDo implements the main verb but drops a qualifier (e.g., "redirect to login" but the requirement says "redirect to login **with a success message**"), the task is incomplete.
13. **Interface consumers exist?** (Phase 2) For every function, class, or component listed in design.md's Components & Interfaces section, verify at least one of: (a) it is consumed by another component in the design's described flows, (b) it is explicitly referenced by a task as a dependency, (c) it is marked as "prepared for Task N" with a forward reference. An interface with none of these is either orphaned (design/implementation mismatch) or speculative (designed for a future that may not come). Flag it.

If a trivial gap is found (formatting, naming), fix it silently. If a **substantive gap** is found (missing test level, orphan requirement, unaddressed security consideration), present it to the user: "During self-review I noticed: [gap]. Add a task or move to Out of Scope?"
