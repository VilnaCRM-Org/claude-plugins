---
name: clean-architecture-llm
description: Use when an assistant writes, generates or reviews Rust code in a layered workspace and must decide which layer a type, module, dependency or model-provider (LLM) integration belongs to, keep the domain framework- and I/O-free, and wire adapters only in the composition root, verified by the boundary check mapped by `make.architecture`. Skip when `architecture.layers` is empty and `architecture.composition_root` is null (no layered workspace). Not for repairing a failing boundary check (use architecture-boundary-fixer), not for aggregate and value-object design (use implementing-ddd-architecture), not for crate, module and file layout (use code-organization).
---

# Clean Architecture for AI-Written Rust

## Profile keys consumed

- `architecture.layers` — the declared layer names, in declaration order, whose responsibilities and permitted dependencies this skill states
- `architecture.composition_root` — the crate that wires adapters to use cases, the only production crate that depends on every layer
- `make.architecture` — the boundary check that verifies the dependency rule

## Context

Use this skill before an assistant writes or reviews Rust code that adds or moves a type, a module, a crate or a dependency, and whenever a model-provider integration (an LLM client, prompt construction, response parsing) enters the service. Generated code drifts in predictable ways: a query in an HTTP handler, the system clock read inside an aggregate, an adapter constructed inside a use case, a new catch-all crate. This skill states where each piece belongs so the boundary check passes by construction, not by repair.

Inputs: the story or the review scope, the profile, and the repository's boundary model in `architecture.toml`, where each layer named in `architecture.layers` has an entry with its crate patterns, the layers it may depend on, the third-party crates it may use and the crates it must not reach even transitively.

## Task

Place every piece of new or changed code in the layer that owns it, keep every dependency pointing inward, and keep construction and wiring in the composition root, so that the target mapped by `make.architecture` reports 0 violations.

## Success criteria

- Every new type, module and crate sits in the layer the responsibilities table below gives it.
- Domain crates are framework- and I/O-free: their manifests list only workspace domain crates and the third-party crates their layer entry allows, and their code performs no I/O.
- Application and infrastructure crates never depend on each other; adapters meet use cases only in the composition root.
- The target mapped by `make.architecture` exits 0 with 0 violations, or, when it is null, the manual manifest check of step 7 is recorded as evidence.
- The verdict line of step 8 is printed.

## Steps

1. **Resolve the profile.** Read the three keys. When `architecture.layers` is empty and `architecture.composition_root` is null, the repository is not a layered workspace: print `SKIPPED: architecture.layers is empty and architecture.composition_root is null`, then `clean-architecture-llm: SUCCESS-WITH-REPORT`, and stop. When only `architecture.layers` is empty, apply the rule below to the crates by their role, never invent layer names or layer crates, and note the missing layer model in the evidence.
2. **Map each layer name to its role.** Take the names from `architecture.layers` and read each one's entry in `architecture.toml`. The layer allowed to depend on nothing outside itself is the domain; the layers that may depend on the domain but not on each other are application and infrastructure; the layer that may depend on all three is the composition root; the layers whose crates exist only for tests or tooling are support layers. A sourced example of the list in a template-derived repository:

   ```yaml # profile-example
   architecture:
     layers: [domain, application, infrastructure, composition-root, test-support, e2e, tooling]
     composition_root: crates/service
   make:
     architecture: architecture   # run as: make architecture
   ```

3. **Place the code by responsibility.**

   | Role | Owns | Never owns |
   | --- | --- | --- |
   | domain | aggregates, entities, value objects, domain events, domain error enums, and every port trait an adapter implements (repository, clock, id generator, cache, event and command buses, a model-provider capability) | web framework types, database drivers, an async runtime, HTTP or provider clients, wire-format serialization, environment reads, file, network or system-clock access, random number generation |
   | application | use cases: commands, queries, their handlers, event subscribers and the context's application error; the API-facing modules (HTTP handlers, request and response types, contract annotations, GraphQL types) when the layer's entry allows the web framework | SQL or driver calls, provider SDK calls, construction of adapters, environment reads, imports from an infrastructure crate |
   | infrastructure | driven adapters that implement domain ports: queries and row mapping, buses, cache, clock, id generator, external and model-provider clients, health probes, retries and timeouts | business rules, use-case orchestration, calls into application handlers |
   | composition root | configuration and command-line parsing, building every adapter, registering handlers and subscribers, assembling routes and middleware, exporting the API contracts | business rules, queries, domain decisions |
   | support layers | test doubles of domain ports, end-to-end suites, repository tooling | anything a production crate needs at run time; production crates reach them only as dev-dependencies |

4. **Keep the dependency rule.** Dependencies point inward and are declared in the manifest of the crate that uses them:

   - **Domain is framework- and I/O-free.** It depends only on other domain crates of its own or a shared context and on the few third-party crates its layer entry allows. Time, identifiers and randomness enter through ports; a port method may be `async`, but the domain never spawns tasks, blocks or opens a connection.
   - **Application** depends on domain and application crates. **Infrastructure** depends on domain and infrastructure crates. The two never depend on each other: a handler cannot run a query and an adapter cannot call a use case.
   - **A bounded context** depends only on itself and on the shared contexts that `architecture.toml` names; contexts talk through domain events on the bus or through shared-kernel types.
   - **The composition root** is the only production crate that depends on all three layers.

5. **Wire in the composition root.** When `architecture.composition_root` is set, every adapter is built and every handler, subscriber and route is registered in the crate at that path, which hands adapters to use cases as port trait objects or generic parameters; new wiring goes there and nowhere else. When it is null, the repository has no dedicated composition-root crate: wire in the binary crate's entry point, keep layer crates free of adapter construction, and record the wiring location in the evidence.
6. **Correct the usual generated-code drift.**

   | Generated code | Where it belongs instead |
   | --- | --- |
   | a query, a pool or a transaction in a use case or HTTP handler | a repository port in domain, its adapter in infrastructure, injected by the composition root |
   | `SystemTime::now()` or a random id created inside domain or a use case | a clock or id-generator port, injected |
   | `std::env::var` in a use case or adapter | typed configuration read in the composition root and passed in |
   | wire-format derives on a domain type | request, response or row types in the outer layer, mapped from the domain type |
   | an adapter calling an application handler | a domain event the use case subscribes to, wired in the composition root |
   | an application crate importing an infrastructure crate to build an adapter | a dependency on the domain port only; the composition root injects the adapter |
   | a new `utils`, `common` or `helpers` crate | the owning context's crate, or a shared-kernel crate of the right layer |
   | a third-party crate added to a domain manifest | the code moves outward to a layer whose entry allows the crate |
   | an import from another bounded context | a domain event or a shared-kernel type |

7. **Place a model-provider capability like any other driven port.** Name the port trait in domain after the business capability (`<Entity>Evaluator`, never after the vendor), with typed request and response value objects and a domain error; the use case in application calls the port; the infrastructure adapter owns the provider client, credentials, model identifiers, prompt templates, timeouts, retries and response parsing, and maps provider failures to the domain error; the composition root selects the adapter from configuration. Default tests use a test double of the port from the support layer and never call a live model.
8. **Verify and report.** Run the target mapped by `make.architecture` as [verification-workflow](../verification-workflow/SKILL.md) prescribes. It exits 0 with 0 violations: `clean-architecture-llm: SUCCESS`. It reports a violation: hand the log to [architecture-boundary-fixer](../architecture-boundary-fixer/SKILL.md), which owns the bounded fix loop and the escalation block; this skill's verdict is that skill's verdict. The key is null: record `not run (capability absent)`, check by hand that each changed crate's `[dependencies]` names only the layers and third-party crates its layer entry allows, record that check as evidence, and end `clean-architecture-llm: SUCCESS-WITH-REPORT`.

## Constraints

- Never put framework, driver, runtime or I/O code in a domain crate, and never add a dependency to a domain manifest to make generated code compile.
- Never let an application crate and an infrastructure crate depend on each other, and never construct an adapter outside the composition root.
- Never edit `architecture.toml` to fit generated code; a needed allow-list change is escalated through [architecture-boundary-fixer](../architecture-boundary-fixer/SKILL.md).
- Never silence the boundary check or a lint to keep generated code; fix the placement.
- Never name a port, a module or a crate after a vendor or a model; name it after the capability.
- Write example contexts as `<group>/<context>` and types as `<Entity>`; read the real names from the repository.

## Verification

```bash
make <make.architecture>
```

The target exits 0 with 0 violations and the output ends with the verdict line of step 8; when the key is null, the manual manifest check is recorded and the verdict is `SUCCESS-WITH-REPORT`.
