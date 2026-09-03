---
id: ADR-0001
status: accepted
date: 2026-07-20
certainty: assumed
assumption: "Migrated; the decision's ruling reference was not found in the status line."
---
# ADR-001: FFI Boundary via flutter_rust_bridge

**Status:** Accepted

## Context
The architecture relies on a strict separation between a stateless Flutter UI and a stateful Rust Core Engine. The boundary must pass complex structures (like Abstract Syntax Trees) constantly, at sub-16ms latency. Manually managing `dart:ffi` pointers and C-structs for recursive AST data is extremely error-prone and severely impacts development velocity.

## Decision
We will use `flutter_rust_bridge` (FRB) v2 to generate the interface bindings.

## Consequences
- **Positive:** Type-safe passing of complex Rust `struct` and `enum` types directly into equivalent Dart classes.
- **Positive:** Eliminates manual memory management and pointer arithmetic.
- **Negative:** Introduces a heavy build-time dependency. The FRB code generation step must be run whenever the Rust API changes.
