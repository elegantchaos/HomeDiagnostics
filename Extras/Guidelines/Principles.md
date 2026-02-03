# Agent principles glossary (for this repo)

This glossary is intended for coding agents working on this project.

It is not meant to override `AGENTS.md`; it expands on the "why" behind common engineering guidance so agents can make sensible tradeoffs when the codebase doesn't explicitly answer a question.

## How to use this

- Apply these principles as heuristics, not strict rules.
- When principles conflict, prefer the principle that best reduces user-visible risk and long-term maintenance cost.
- If a change increases complexity, be explicit about why the complexity is necessary.

## Principles

### Occam's Razor / KISS

Prefer the simplest implementation that satisfies the requirements.

Signals you're violating it:
- You're adding new abstractions "just in case".
- You're creating generic infrastructure to solve a one-off.

Good examples:
- Keep command wiring local until it repeats.
- Avoid introducing a new command framework or dispatcher layer unless the CLI surface demands it.

### YAGNI

Don't build optionality or extensibility until you have a concrete need.

Use it to decide:
- Whether to add a protocol now vs. wait.
- Whether a type should be `public` or remain `internal`.

### DRY (balanced with clarity)

Avoid duplication when it reduces bugs and maintenance.

Practical guidance:
- Deduplicate logic (behavior) sooner than you deduplicate output formatting.
- Avoid "DRYing" unrelated code into an abstraction that hides intent.
- In tests, deduplicate expensive setup and repeated literals (but keep assertions explicit).

### Single Source of Truth

Keep authoritative state in one place; compute derived state from it.

In a CLI:
- Prefer storing the minimal mutable state in a command input model.
- Keep formatted output and "isEnabled" style values derived.

### Make Invalid States Unrepresentable

Use the type system to prevent illegal states.

Techniques:
- Use enums for state machines.
- Use typed identifiers (enums, wrappers) instead of raw strings.
- Use non-optional properties when a value must exist.

### SOLID (focus: SRP + DIP)

- SRP (Single Responsibility Principle): types should have one reason to change.
- DIP (Dependency Inversion Principle): high-level logic depends on abstractions, not concrete details.

In this repo:
- Command handlers depend on protocols for services (filesystem, persistence, clock, networking, process runner) when it improves testability.
- Keep I/O boundaries explicit and isolate side effects in a few well-named types.

### Dependency Injection

Prefer explicit dependencies over hidden globals.

Practical defaults:
- Constructor injection for command handlers/services.
- Protocol boundaries around I/O (filesystem, networking, process execution, time, environment).
- Avoid singletons unless the codebase already standardizes on one.

### Composition over Inheritance

Prefer composing small types and protocol conformances over deep class hierarchies.

In Swift:
- Prefer protocols + extensions for behavior.
- Prefer small helper types over base classes.

### Command–Query Separation

Separate "doing" from "calculating".

Guidance:
- A method that mutates state should return `Void` (or a narrow result) rather than also returning complex derived values.
- Use separate computed properties/functions for derived data.

### Principle of Least Knowledge (Law of Demeter)

Minimize how much one part of the code knows about another.

In practice:
- Pass value types across module boundaries.
- Avoid leaking third-party types (like argument parser models) across module boundaries unless required.

### Pit of Success APIs

Design APIs so the easiest path is the correct one.

Examples:
- Strongly typed identifiers for paths, commands, or configuration keys.
- Wrapper types that ensure validation ordering or prevent skipping required steps.

### Concurrency-by-Design

Be explicit about concurrency boundaries.

Guidance:
- Keep concurrency boundaries explicit and deterministic.
- Shared mutable state: an actor.
- Avoid shared global mutable state.
- Prefer Swift concurrency primitives over GCD.
- Avoid concurrency when the CLI output ordering is user-facing or part of tests.

### Deterministic Output

Given the same inputs, produce the same stdout, stderr, and exit code.

Signals you're violating it:
- Output ordering changes across runs without input changes.
- Errors are printed to stdout or differ in phrasing across code paths.

Good examples:
- Stable sorting of results when order is not inherently meaningful.
- Consistent error prefixes and exit codes.

### Exit Codes as API

Treat exit status and stderr as part of the public contract.

Guidance:
- Use non-zero exit codes for failures.
- Reserve stdout for machine-readable output when appropriate.
- Keep stderr human-readable and actionable.

### Fast Failure, Clear Errors

Validate inputs early and fail with context that helps users recover.

Examples:
- Validate file paths and permissions before doing work.
- Tell the user which flag/argument is invalid and why.

### Pipeline-Friendly Behavior

Make commands composable in pipelines.

Guidance:
- Avoid interactive prompts unless explicitly requested.
- Support reading from stdin when it matches CLI conventions.
- Keep output free of extra noise unless a verbose flag is set.

## Decision heuristics (when unsure)

- Prefer correctness and user safety over micro-optimizations.
- Prefer a smaller surface area (`internal` by default; keep `public` APIs intentional).
- Prefer local changes over cross-cutting refactors.
- Prefer patterns already used in the codebase.

## Writing guidance (for agent outputs)

- Explain tradeoffs briefly when changing architecture.
- Keep diffs small and focused.
- If you introduce a new abstraction, point to the specific duplication/bug risk it addresses.
