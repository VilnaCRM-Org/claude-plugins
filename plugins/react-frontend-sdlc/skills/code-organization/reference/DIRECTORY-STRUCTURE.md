# Frontend Directory Structure Reference

**Learn where to place files in a modular bulletproof-react frontend by
following the ownership-first placement law.** This is the full
folder-by-folder companion to the [code-organization skill](../SKILL.md);
its Core Principle governs every decision below:

> **Place code by ownership first, then by kind — a feature owns its code,
> and a folder holds ONLY the kind of thing its name promises.**

Every concrete path is resolved through the project profile
(`architecture.source_root`, `architecture.modules`,
`architecture.component_prefix`, `architecture.path_aliases`) rather than
hardcoded. `<module>` below stands for any entry of
`architecture.modules`; `<feature>` stands for any feature directory under
that module; `<prefix-lower>` is `architecture.component_prefix`
lowercased (default `UI` → `ui-`). The examples use generic module names
(`catalog`, `checkout`) and a generic feature (`auth`) — substitute the
module and feature the story names.

## Two questions, in order

Placement is always two decisions, taken in this sequence — never the
reverse:

1. **Who OWNS it?** A feature owns its code by default. Promote to a
   shared layer only on real demand from two or more callers, and keep a
   reusable `components/` primitive free of any feature dependency.
2. **What KIND is it?** Once the owner is fixed, the folder is fixed too —
   a folder holds only the kind its name promises. A hook goes in
   `hooks/`, a type-only file in a `types/` folder, data access in
   `repositories/`. Anything else fails the allowed-folder gate.

## Quick Reference: "I'm creating X → it goes HERE"

| I'm creating a…           | It goes HERE                                                              | Why (kind)                                        |
| ------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------- |
| Reusable UI component     | `<source_root>/components/<prefix-lower>-<name>/index.tsx`                | shared, feature-free presentation                 |
| Feature component         | `<source_root>/modules/<module>/features/<feature>/components/<name>.tsx` | feature-owned UI                                  |
| Hook                      | `…/features/<feature>/hooks/use-<name>.ts(x)`                             | owns data / effects / state for components        |
| Store / reactive var      | `<source_root>/modules/<module>/store/<name>.ts`                          | module state + composition root                   |
| Repository                | `…/features/<feature>/repositories/<name>-repository.ts` (public `index`) | the only layer that talks to the API              |
| Service (singleton infra) | `<source_root>/services/<name>/`                                          | cross-module infrastructure                       |
| Mapper (response / error) | `…/modules/<module>/store/` or `…/modules/<module>/lib/`                  | instance-method class, shared by the module       |
| Factory                   | same feature area as the object it builds (`repositories/` or `utils/`)   | `<Object>Factory` next to `<Object>`              |
| Type / interface          | a `types/` folder (feature, module, or `components/types/`)               | type-only file, imported via `import type`        |
| Validation schema         | `…/features/<feature>/utils/<name>-schemas.ts`                            | runtime — a schema is logic, not a type file      |
| GraphQL document          | `…/features/<feature>/repositories/`                                      | co-located with the repository that sends it      |
| Test                      | `tests/…` mirroring the subject's owner + environment                     | mirror source ownership                           |
| Story                     | `*.stories.tsx` co-located next to the component                          | Storybook picks up `<source_root>/**/*.stories.*` |

When a row is non-obvious, stop and re-read the folder descriptions below —
the placement is almost always telling you which owner or kind you skipped.

## Placement Decision Tree

```text
What does the file DO?

├─ Renders UI reused across ≥2 modules (no feature copy)? → components/<prefix-lower>-*/
├─ Renders feature UI? ................................... modules/<module>/features/<feature>/components/
├─ Owns data / side effects / state for components? ..... a hook (features/<feature>/hooks/use-*.ts)
├─ Talks to the API? .................................... features/<feature>/repositories/ (consumed via index)
├─ Holds module state? ................................. modules/<module>/store/ (+ composition root)
├─ Cross-module singleton infrastructure? .............. services/<name>/
├─ Declares a type only? ............................... a types/ folder (import type)
├─ Pure transformation / decision / validation schema? . instance method in utils/ or lib/
├─ A user-facing string? ............................... feature i18n/{en,uk}.json
└─ Something else? ..................................... confirm against the allowed-folder set FIRST
```

## Complete Directory Structure

```text
<architecture.source_root>/
├── modules/                          ← one directory per architecture.modules entry
│   └── <module>/                     ← e.g. catalog, checkout (lowercase kebab-case)
│       ├── config/                   ← module-scoped configuration
│       ├── features/
│       │   └── <feature>/            ← e.g. auth (lowercase kebab-case)
│       │       ├── assets/           ← static assets (svg, images)
│       │       ├── components/       ← feature UI (React components)
│       │       ├── hooks/            ← use-* / index only
│       │       ├── i18n/             ← en.json, uk.json
│       │       ├── repositories/     ← data access (consumed via index)
│       │       ├── routes/           ← route components / definitions
│       │       ├── types/            ← type-only files
│       │       └── utils/            ← instance-method helper classes, schemas
│       ├── hooks/                    ← module-shared hooks
│       ├── lib/                      ← module-shared logic (named classes)
│       ├── store/                    ← module state + composition root + mappers
│       ├── types/                    ← module-shared type-only files
│       ├── utils/                    ← module-shared utilities
│       └── package.json              ← module metadata
├── components/                       ← reusable <component_prefix>* UI (feature-free)
├── features/                         ← shared cross-module features
├── services/                         ← singleton infrastructure services (HTTP client, …)
├── config/                           ← DI container config, tokens, api config
├── routes/                           ← app-level route definitions
├── providers/                        ← React context providers
├── styles/                           ← theme / design tokens for framework.ui
└── utils/                            ← shared cross-cutting utilities (specific names)
```

## Folder-by-Folder: what each holds (and must NOT hold)

### `modules/<module>/` — the feature module

A module owns its code. Its root may contain ONLY these directories:
`config`, `features`, `hooks`, `lib`, `store`, `types`, `utils`, plus a
`package.json` for metadata. Anything else fails `module-allowed-folders`.

- **Holds**: feature subtrees, module-shared hooks / logic / state /
  types / utilities, and the module's `package.json`.
- **Must NOT hold**: a `helpers/`, `misc/`, `common/`, or `manager/`
  catch-all; an `api/` folder (data access is `repositories/` inside a
  feature); ad-hoc top-level folders. Shared module code goes in `lib/` or
  `utils/` with a specific file name — never `helpers/`.

### `modules/<module>/features/<feature>/` — one feature

A feature root may contain ONLY: `assets`, `components`, `hooks`, `i18n`,
`repositories`, `routes`, `types`, `utils`. Anything else fails
`feature-allowed-folders`.

| Folder          | Holds ONLY                                             | Must NOT hold                                               |
| --------------- | ------------------------------------------------------ | ----------------------------------------------------------- |
| `components/`   | React components (feature UI, `*.tsx`)                 | hooks, repositories, type-only files, module state          |
| `hooks/`        | `use-*.ts(x)` or `index.*` hook files                  | non-hook helpers or types (`feature-hooks-file-convention`) |
| `repositories/` | data-access classes, reached via `index` only          | UI, hooks, direct calls from components                     |
| `routes/`       | route components / definitions for the feature         | business logic, data access                                 |
| `types/`        | type-only files (`interface` / `type` / `import type`) | any runtime (`const` / `function` / `class`)                |
| `utils/`        | instance-method helper classes, validation schemas     | vague `utils.ts` / `helper.ts`; free functions              |
| `i18n/`         | `en.json`, `uk.json`                                   | code                                                        |
| `assets/`       | static assets                                          | code                                                        |

Feature state does not live here — the store stays at module level. Do not
add a feature-level `store/`, an `api/`, or a `helpers/`.

### `modules/<module>/store/` — module state

The single home for the module's state (`framework.state`), its
composition root, and the shared response / error mappers. The composition
root is the only place that touches the `framework.di` container, behind a
dynamic `import()`, so the paint path stays container-free. Mappers here
are instance-method classes.

### Shared top-level layers

| Folder        | Holds ONLY                                                    | Must NOT hold                                          |
| ------------- | ------------------------------------------------------------- | ------------------------------------------------------ |
| `components/` | reusable `<component_prefix>*` UI building blocks             | any feature i18n, store, repository types, route state |
| `features/`   | shared cross-module features                                  | module-specific code                                   |
| `services/`   | singleton infrastructure services (the shared HTTP client, …) | feature or UI logic; direct callers other than repos   |
| `config/`     | DI container config, tokens, api config                       | business logic                                         |
| `routes/`     | app-level route definitions                                   | feature UI                                             |
| `providers/`  | React context providers                                       | data access, business logic                            |
| `styles/`     | theme / design tokens / global styles for `framework.ui`      | component-specific one-off styles                      |
| `utils/`      | shared cross-cutting utilities with specific names            | a `utils.ts` / `helpers/` catch-all                    |

A reusable `components/` primitive carries **no** feature dependency: no
feature i18n, no module store, no repository types, no route state. The
moment a component needs feature-specific props, copy, or state, it belongs
to that feature, not here.

## File and identifier naming

> **Files and folders are lowercase kebab-case; exported identifiers carry
> their role in the name.**

| Kind                  | File pattern                       | Identifier                            | Example                                      |
| --------------------- | ---------------------------------- | ------------------------------------- | -------------------------------------------- |
| Reusable UI component | `<prefix-lower>-<kebab>/index.tsx` | PascalCase `<component_prefix><Name>` | `ui-button/index.tsx` → `UIButton`           |
| Feature component     | `<kebab>.tsx`                      | PascalCase                            | `login-card.tsx` → `LoginCard`               |
| Hook                  | `use-<kebab>.ts(x)` or `index.*`   | `use<Name>`                           | `use-login-switcher.ts` → `useLoginSwitcher` |
| Repository            | `<kebab>-repository.ts`            | class `<Name>Repository`              | `login-repository.ts` → `LoginRepository`    |
| Store / reactive var  | `<kebab>.ts`                       | class + module singleton              | `auth-var.ts` → `AuthStateVar`               |
| Selectors             | `<kebab>-selectors.ts`             | class singleton                       | `auth-store-selectors.ts`                    |
| Mapper                | `<kebab>-mapper.ts`                | class `<Name>Mapper`                  | `auth-response-mapper.ts`                    |
| Factory               | `<kebab>-factory.ts`               | class `<Object>Factory`               | `auth-error-factory.ts` → `AuthErrorFactory` |
| Helper / util         | `<specific-kebab>.ts`              | class with instance methods           | `normalize-auth-error.ts`                    |
| Validation schema     | `<kebab>-schemas.ts`               | schema value(s) in a class            | `response-schemas.ts`                        |
| Type-only file        | `types/<area>/<kebab>.ts`          | `interface` / `type` only             | `types/ui-form/submit-controls.ts`           |
| i18n                  | `i18n/{en,uk}.json`                | —                                     | `i18n/en.json`                               |
| Test                  | mirror subject + environment       | —                                     | `normalize-auth-error.test.ts`               |
| Story                 | `<kebab>.stories.tsx`              | —                                     | `ui-button/index.stories.tsx`                |

Module and feature directory names are lowercase kebab-case
(`back-to-main`, not `BackToMain`; `auth`, not `Auth`) — enforced by
`no-uppercase-paths`, `src-module-name-kebab-case`, and
`src-feature-name-kebab-case`. Give helpers specific names that state the
transformation or decision they perform; never `helper`, `misc`, `data`,
or a bare `utils`.

## Type-only files

> **Types live in dedicated `types.ts` files or per-area `types/` folders
> and are imported back via `import type`; logic files declare no
> `interface` / `type`.**

A component's prop type does not live beside the component — it moves to the
owning feature's (or module's, or `components/types/`) `types/` folder,
grouped one level by source area, and is imported with `import type`.
Type-only files contain only type-level constructs (`interface`, `type`,
`import type`, type re-exports, `declare`) and never runtime
(`const` / `function` / `class`). Conversely, a logic file must not declare
or export an `interface` / `type`.

```typescript
// ❌ WRONG: a logic file declaring its own prop type
// File: components/submit-controls.tsx
interface SubmitControlsProps { busy: boolean }

// ✅ CORRECT: the type moves to the feature's types/ folder
// File: types/ui-form/submit-controls.ts
export interface SubmitControlsProps { busy: boolean }
// File: components/submit-controls.tsx
import type { SubmitControlsProps } from '@/…/types/ui-form/submit-controls';
```

Runtime that once co-located under `types/` is relocated by kind: a
validation schema and its validators go to the feature's
`utils/*-schemas.ts`, a GraphQL document goes to the feature's
`repositories/`, and error classes go to the module's `lib/`. This split is
enforced by ESLint and by `dependency-cruiser`
(`type-files-imported-as-type-only`, `type-files-no-runtime-imports`):
type files may be imported only with `import type` and must not depend on
runtime modules.

## Classes with instance methods, not free functions or `static`

> **Non-React `*.ts` (services, repositories, mappers, factories, stores,
> utilities) uses instance methods on a class — never a `static` member and
> never a standalone (free) function.**

Behavioral collaborators are `@injectable()` classes registered against a
token and resolved through the `framework.di` container, so tests substitute
them by swapping the binding rather than monkey-patching a module.
Render-path state primitives that must stay container-free are instance
classes exported as a module singleton, so call sites stay `X.method(…)`
without pulling the container into the paint chunk.

```typescript
// ❌ WRONG: free functions in a non-React .ts file (and a catch-all name)
export function validateEmail() {}
export function formatName() {}

// ✅ CORRECT: instance methods on specific, named classes
class EmailValidator {
  public validate(value: string): boolean {
    /* … */
  }
}
const emailValidator = new EmailValidator();
export default emailValidator;
```

**Exempt** — because they are functions by definition: React components
(`*.tsx`, including class error boundaries that need
`static getDerivedStateFromError`) and hooks (`use-*.ts(x)`). Everywhere
else the ESLint `no-restricted-syntax` gate (run by the target mapped by
`make.lint_eslint`) fails the build on `static` members and free functions —
fix by refactoring to an instance method, never with a suppression
directive.

## Path aliases and the module / feature public API boundary

Follow the bulletproof-react import convention; the configured aliases live
in `architecture.path_aliases` and are wired into the TypeScript config, the
bundler, and Jest.

- **Same folder** → a relative import (`./sibling`).
- **Cross-folder / cross-feature** → the project-wide alias (e.g. `@/…`).
- **Deep within one feature** → the optional feature-scoped alias (e.g.
  `@auth/…`), so imports stay readable and within the line-length budget.
- **Avoid** deep relative chains like `../../../X` — reach for an alias.

Crossing a **module or feature boundary is allowed only through its `index`
barrel** — the bare module / feature alias is its public API entry point.
A deep import that reaches past the barrel into another module's or
feature's internals, or past a repository's `index`, is a
`dependency-cruiser` violation (`no-cross-module-imports`,
`no-cross-feature-imports`, `no-repository-internal-imports`) reported by
the target mapped by `make.lint_deps`, whose `quality.depcruise_violations`
ceiling is fixed at `0`. The DI composition root and the app-shell router's
code-split route / guard entries are the only sanctioned exceptions.

```text
✅ import { LoginRepository } from '@/modules/checkout/features/auth';  // via the barrel
❌ import { LoginRepository } from '@/modules/checkout/features/auth/repositories/login-repository';
```

## Creating new files: step-by-step

### Adding a feature to a module

```text
<source_root>/modules/<module>/features/<feature>/
├── components/
│   ├── <feature>-form.tsx            ← renders props + translated UI
│   └── <feature>-form-fields.tsx     ← renders fields
├── hooks/
│   └── use-<feature>-form.ts         ← owns data + side effects + state
├── repositories/
│   ├── index.ts                      ← public API of the data layer
│   └── <feature>-repository.ts       ← talks to the shared HTTP client
├── types/
│   └── <feature>-form/fields.ts      ← type-only prop / DTO shapes
├── utils/
│   └── response-schemas.ts           ← runtime validation schemas
└── i18n/
    ├── en.json
    └── uk.json
```

The hook is the only place that resolves repositories or store actions; the
component stays a pure render of translated props. The component reaches
data and state **through the hook** — never by importing the module store,
a repository, or `services/` directly (`no-components-to-store`,
`no-components-to-repositories`, `no-feature-ui-to-services`).

### Promoting a reusable component

Move a component to `<source_root>/components/<prefix-lower>-<name>/` only
once two or more modules use it **without** feature-specific props, copy, or
state, and strip every feature dependency on the way out.

```text
❌ <source_root>/components/login-card.tsx        # imports feature i18n + repo types
✅ <source_root>/modules/<module>/features/<feature>/components/login-card.tsx
```

## Anti-patterns: wrong file placement

### Vague catch-all folder or name

```text
❌ <source_root>/modules/<module>/features/<feature>/utils/utils.ts
✅ <source_root>/modules/<module>/features/<feature>/utils/normalize-auth-error.ts
✅ <source_root>/modules/<module>/features/<feature>/utils/map-validation-errors.ts
```

`helpers/`, `misc/`, `common/`, `manager/` folders and `helper` / `util` /
`misc` file names are rejected — extract a specific responsibility into a
named class in `lib/` or `utils/`.

### Uppercase or non-kebab path

```text
❌ src/modules/BackToMain/Features/Auth/
✅ src/modules/back-to-main/features/auth/
```

### Business logic inside a component

A component that resolves a repository, owns form state, maps errors, AND
renders violates the boundary. Move data + side effects + state into a
`use-*` hook and leave the component a pure render — the layered
Component → Hook → Repository → API flow.

## How this ties to the gates

| Symptom / gate                                     | Placement fix                                                                                                                                                               |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `dependency-cruiser` violation (`make.lint_deps`)  | Wrong folder, disallowed folder, or a cross-boundary / deep import — move the file or route through the `index` barrel (`quality.depcruise_violations` = `0`)               |
| ESLint `no-restricted-syntax` (`make.lint_eslint`) | A `static` member or free function in non-React `.ts`, or `data-testid` in source — refactor to an instance method; query by role / label / text                            |
| Type-file gate (ESLint + dependency-cruiser)       | Runtime in a type file, or a type in a logic file — move runtime out; import types via `import type`                                                                        |
| jscpd clone (`make.lint_dup`)                      | Duplicated block at or above the threshold — deduplicate by extracting a shared component, hook, or constant (`quality.jscpd_clones` = `0`)                                 |
| TypeScript error after a move                      | Update imports and aliases everywhere so `quality.tsc_errors` stays `0`                                                                                                     |
| Complexity gate (`make.lint_metrics`)              | A split left a unit over budget — extract a hook or a named helper class while `quality.metrics_enforced` stays `true` (see the [complexity-management skill](../SKILL.md)) |

Ceilings are fixed and floors are raise-only: a profile may tighten a
threshold, never relax it — fix the code and its placement, never the gate.

## Quick checks

```bash
# Placement, naming, and import boundaries:
#   run the target mapped by make.lint_deps (dependency-cruiser)
#   must report quality.depcruise_violations (= 0)

# Convention gates (no-static / no-free-function / no-data-testid / type-file):
#   run the target mapped by make.lint_eslint

# Types: run the target mapped by make.lint_tsc — quality.tsc_errors (= 0)
# DRY:   run the target mapped by make.lint_dup — quality.jscpd_clones (= 0)
# Complexity: run the target mapped by make.lint_metrics (quality.metrics_enforced)

# Find organizational smells (generic tooling)
grep -rn "data-testid" <architecture.source_root>/                        # forbidden in source
grep -rEn "/(helpers|misc|common|manager)/" <architecture.source_root>/   # catch-all folders
grep -rEn "\.\./\.\./\.\." <architecture.source_root>/                     # deep relative chains
```

If a `make.*` mapping is `null`, the capability is absent — note the skip
and fall back to the remaining checks instead of inventing a target.

## Related documentation

See the [code-organization skill](../SKILL.md) for the surrounding
conventions — the allowed-folder law, the verification checklist, the DI
and factory patterns, and the hardcoded-value / i18n extraction rules that
this placement reference supports.

---

**Remember**: Structure reflects intent. Owner-first placement and truthful
folder names make the architecture self-documenting.
