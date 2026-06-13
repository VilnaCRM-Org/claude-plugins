# DDD Directory Structure Reference

**Learn where to place files in a Domain-Driven Design architecture by
following proven patterns from
[CodelyTV's php-ddd-example](https://github.com/CodelyTV/php-ddd-example).**

> Repository implementations and mapping files follow the profile's
> `persistence.mapper`: `doctrine-orm` repositories with `.orm.xml`
> mappings, or `doctrine-odm` repositories with `.mongodb.xml` mappings —
> the directory layout is identical either way.

## Quick Reference: File Placement Decision Tree

```text
Is it business logic?
├─ YES → Domain layer
│   ├─ Has identity? → Entity (Domain/Entity/)
│   ├─ No identity, immutable? → Value Object (Domain/ValueObject/)
│   ├─ Cluster of entities? → Aggregate (Domain/Entity/, extends AggregateRoot)
│   ├─ Something happened? → Domain Event (Domain/Event/)
│   ├─ Data access contract? → Repository Interface (Domain/Repository/)
│   └─ Business error? → Domain Exception (Domain/Exception/)
│
├─ Is it orchestration/use case?
│   ├─ YES → Application layer
│   │   ├─ Write operation? → Command + Handler (Application/Command/, Application/CommandHandler/)
│   │   ├─ Read operation? → Query + Handler (Application/Query/, Application/QueryHandler/)
│   │   ├─ React to event? → Event Subscriber (Application/EventSubscriber/)
│   │   ├─ API transformation? → DTO/Processor (Application/DTO/, Application/Processor/)
│   │   └─ GraphQL input? → Mutation Input (Application/MutationInput/, when framework.graphql)
│   │
└─ Is it technical/external concern?
    └─ YES → Infrastructure layer
        ├─ Database access? → Repository Implementation (Infrastructure/Repository/)
        ├─ Message dispatching? → Bus Implementation (Infrastructure/Bus/)
        ├─ Doctrine type? → Custom Type (Infrastructure/DoctrineType/)
        └─ External service adapter? → Infrastructure adapter (named after its
           pattern — never a vague `Service/` catch-all; see code-organization)
```

## Complete Directory Structure (CodelyTV Pattern)

```text
src/
├── Mooc/                           # Bounded Context (Application)
│   ├── Courses/                    # Module (Aggregate Root)
│   │   ├── Application/            # Use cases & orchestration
│   │   │   ├── Create/             # Use case: Create Course
│   │   │   │   ├── CreateCourseCommand.php
│   │   │   │   ├── CreateCourseCommandHandler.php
│   │   │   │   └── CourseCreator.php
│   │   │   ├── Find/               # Use case: Find Course
│   │   │   │   ├── FindCourseQuery.php
│   │   │   │   ├── FindCourseQueryHandler.php
│   │   │   │   └── CourseFinder.php
│   │   │   └── Update/             # Use case: Update Course
│   │   │       ├── CourseRenamer.php
│   │   │       └── RenameCourseCommandHandler.php
│   │   │
│   │   ├── Domain/                 # Pure business logic
│   │   │   ├── Course.php                    # Aggregate Root entity
│   │   │   ├── CourseId.php                  # Value Object (ID)
│   │   │   ├── CourseName.php                # Value Object
│   │   │   ├── CourseDuration.php            # Value Object
│   │   │   ├── CourseCreatedDomainEvent.php  # Domain Event
│   │   │   ├── CourseNotExist.php            # Domain Exception
│   │   │   └── CourseRepository.php          # Repository Interface
│   │   │
│   │   └── Infrastructure/         # Technical implementations
│   │       ├── Persistence/
│   │       │   ├── DoctrineCourseRepository.php
│   │       │   └── FileCourseRepository.php
│   │       └── Mapping/
│   │           └── Course.orm.xml
│   │
│   ├── Videos/                     # Another Module
│   │   ├── Application/
│   │   ├── Domain/
│   │   └── Infrastructure/
│   │
│   └── Shared/                     # Shared within Mooc context
│       ├── Domain/
│       │   └── Criteria/
│       └── Infrastructure/
│
├── Backoffice/                     # Another Bounded Context
│   ├── Courses/
│   │   ├── Application/
│   │   ├── Domain/
│   │   └── Infrastructure/
│   └── Shared/
│
└── Shared/                         # Shared Kernel (cross-context)
    ├── Domain/
    │   ├── Aggregate/
    │   │   └── AggregateRoot.php
    │   ├── Bus/
    │   │   ├── Command/
    │   │   │   ├── CommandInterface.php
    │   │   │   ├── CommandBusInterface.php
    │   │   │   └── CommandHandlerInterface.php
    │   │   ├── Event/
    │   │   │   ├── DomainEvent.php
    │   │   │   ├── EventBusInterface.php
    │   │   │   └── DomainEventSubscriberInterface.php
    │   │   └── Query/
    │   │       ├── QueryInterface.php
    │   │       ├── QueryBusInterface.php
    │   │       └── QueryHandlerInterface.php
    │   ├── Collection/
    │   │   └── Collection.php
    │   ├── ValueObject/
    │   │   ├── Ulid.php
    │   │   ├── StringValueObject.php
    │   │   └── IntValueObject.php
    │   ├── Exception/
    │   │   └── DomainException.php
    │   └── Criteria/
    │       ├── Criteria.php
    │       ├── Filter.php
    │       └── Order.php
    │
    ├── Application/
    │   ├── Transformer/
    │   ├── Validator/
    │   └── OpenApi/
    │       ├── Factory/
    │       └── Processor/
    │
    └── Infrastructure/
        ├── Bus/
        │   ├── Command/
        │   │   └── InMemoryCommandBus.php
        │   └── Event/
        │       └── SymfonyEventBus.php
        ├── DoctrineType/
        │   ├── UlidType.php
        │   └── DomainUuidType.php
        └── Persistence/
            └── Doctrine/
```

## Profile-Adapted Project Structure

The concrete tree comes from the profile: one top-level directory per
entry in `architecture.bounded_contexts` under
`architecture.source_root`, plus a shared kernel named by
`architecture.shared_context` (when set). `Customer` below stands for
any bounded context:

```text
<architecture.source_root>/
├── Customer/                       # Bounded Context (from architecture.bounded_contexts)
│   ├── Application/                # Use cases
│   │   ├── Command/                # Write operations
│   │   │   ├── CreateCustomerCommand.php
│   │   │   └── UpdateCustomerCommand.php
│   │   ├── CommandHandler/         # Handle commands
│   │   │   ├── CreateCustomerHandler.php
│   │   │   └── UpdateCustomerHandler.php
│   │   ├── DTO/                    # Data Transfer Objects
│   │   │   └── CustomerInput.php
│   │   ├── EventSubscriber/        # React to domain events
│   │   │   └── SendWelcomeEmailOnCustomerCreated.php
│   │   ├── Processor/              # API state processors (framework.api_platform)
│   │   │   └── CreateCustomerProcessor.php
│   │   ├── Resolver/               # GraphQL resolvers (framework.graphql)
│   │   │   └── CustomerResolver.php
│   │   ├── MutationInput/          # GraphQL inputs (framework.graphql)
│   │   │   └── CreateCustomerInput.php
│   │   ├── Transformer/            # Data transformations
│   │   │   └── CustomerToArrayTransformer.php
│   │   └── Factory/                # Object factories
│   │       └── CustomerFactory.php
│   │
│   ├── Domain/                     # Pure business logic
│   │   ├── Entity/                 # Domain entities
│   │   │   └── Customer.php
│   │   ├── ValueObject/            # Value objects
│   │   │   ├── Email.php
│   │   │   ├── CustomerName.php
│   │   │   └── LoyaltyPoints.php
│   │   ├── Event/                  # Domain events
│   │   │   ├── CustomerCreated.php
│   │   │   └── CustomerEmailChanged.php
│   │   ├── Repository/             # Repository interfaces
│   │   │   └── CustomerRepositoryInterface.php
│   │   ├── Exception/              # Domain exceptions
│   │   │   ├── InvalidEmailException.php
│   │   │   └── CustomerNotFoundException.php
│   │   ├── Collection/             # Domain collections
│   │   │   └── CustomerCollection.php
│   │   └── Factory/                # Domain factories (interfaces)
│   │       └── CustomerFactoryInterface.php
│   │
│   └── Infrastructure/             # Technical implementations
│       └── Repository/             # Repository implementations
│           └── DoctrineCustomerRepository.php   # {Technology}{Entity}Repository
│
└── <architecture.shared_context>/  # Shared kernel (when set)
    ├── Application/
    │   ├── Transformer/
    │   ├── Validator/
    │   ├── ErrorProvider/
    │   └── OpenApi/
    │       ├── Factory/
    │       ├── Builder/
    │       └── Processor/
    │
    ├── Domain/
    │   ├── Aggregate/
    │   │   └── AggregateRoot.php
    │   ├── Bus/
    │   │   ├── Command/
    │   │   │   ├── CommandInterface.php
    │   │   │   ├── CommandBusInterface.php
    │   │   │   └── CommandHandlerInterface.php
    │   │   └── Event/
    │   │       ├── DomainEvent.php
    │   │       ├── EventBusInterface.php
    │   │       └── DomainEventSubscriberInterface.php
    │   ├── ValueObject/
    │   │   └── Ulid.php
    │   └── Exception/
    │       └── DomainException.php
    │
    └── Infrastructure/
        ├── Bus/
        │   ├── Command/
        │   │   └── SymfonyCommandBus.php
        │   └── Event/
        │       └── SymfonyEventBus.php
        ├── DoctrineType/
        │   ├── UlidType.php
        │   └── DomainUuidType.php
        └── Transformer/
```

## File Naming Conventions

### Domain Layer

| Type                 | Naming Pattern                    | Example                           |
| -------------------- | --------------------------------- | --------------------------------- |
| Entity               | `{EntityName}.php`                | `Customer.php`                    |
| Value Object         | `{ConceptName}.php`               | `Email.php`, `Money.php`          |
| Domain Event         | `{Entity}{PastTenseAction}.php`   | `CustomerCreated.php`             |
| Repository Interface | `{Entity}RepositoryInterface.php` | `CustomerRepositoryInterface.php` |
| Domain Exception     | `{SpecificError}Exception.php`    | `InvalidEmailException.php`       |
| Collection           | `{Entity}Collection.php`          | `CustomerCollection.php`          |

### Application Layer

| Type             | Naming Pattern                  | Example                                   |
| ---------------- | ------------------------------- | ----------------------------------------- |
| Command          | `{Action}{Entity}Command.php`   | `CreateCustomerCommand.php`               |
| Command Handler  | `{Action}{Entity}Handler.php`   | `CreateCustomerHandler.php`               |
| Event Subscriber | `{Action}On{Event}.php`         | `SendEmailOnCustomerCreated.php`          |
| DTO              | `{Entity}{Type}.php`            | `CustomerInput.php`, `CustomerOutput.php` |
| Processor        | `{Action}{Entity}Processor.php` | `CreateCustomerProcessor.php`             |
| Transformer      | `{From}To{To}Transformer.php`   | `CustomerToArrayTransformer.php`          |

### Infrastructure Layer

| Type               | Naming Pattern                       | Example                          |
| ------------------ | ------------------------------------ | -------------------------------- |
| Repository         | `{Technology}{Entity}Repository.php` | `DoctrineCustomerRepository.php` |
| Doctrine Type      | `{ConceptName}Type.php`              | `UlidType.php`                   |
| External Adapter   | `{Provider}{Pattern}.php`            | `StripePaymentGateway.php`       |
| Bus Implementation | `{Framework}{Type}Bus.php`           | `SymfonyCommandBus.php`          |

## Creating New Files: Step-by-Step

### Creating a New Bounded Context

New contexts must be added to `architecture.bounded_contexts` in the
profile so every other skill sees them.

```bash
# 1. Create directory structure (Order = new context name)
mkdir -p <architecture.source_root>/Order/{Application/{Command,CommandHandler,EventSubscriber,DTO},Domain/{Entity,ValueObject,Event,Repository,Exception},Infrastructure/Repository}

# 2. Result:
<architecture.source_root>/Order/
├── Application/
│   ├── Command/
│   ├── CommandHandler/
│   ├── EventSubscriber/
│   └── DTO/
├── Domain/
│   ├── Entity/
│   ├── ValueObject/
│   ├── Event/
│   ├── Repository/
│   └── Exception/
└── Infrastructure/
    └── Repository/
```

### Adding a New Entity

Mapping file suffix follows `persistence.mapper` (`.orm.xml` for
`doctrine-orm`, `.mongodb.xml` for `doctrine-odm`); the repository class
prefix names the actual technology.

1. **Entity** (Domain): `<source_root>/Order/Domain/Entity/Order.php`
2. **Value Objects** (Domain): `<source_root>/Order/Domain/ValueObject/OrderId.php`, etc.
3. **Repository Interface** (Domain): `<source_root>/Order/Domain/Repository/OrderRepositoryInterface.php`
4. **Domain Events** (Domain): `<source_root>/Order/Domain/Event/OrderPlaced.php`
5. **Exceptions** (Domain): `<source_root>/Order/Domain/Exception/InvalidOrderException.php`
6. **Doctrine Mapping** (Config): `config/doctrine/Order.<mapper-suffix>.xml`
7. **Repository Implementation** (Infrastructure): `<source_root>/Order/Infrastructure/Repository/DoctrineOrderRepository.php`
8. **Command** (Application): `<source_root>/Order/Application/Command/PlaceOrderCommand.php`
9. **Handler** (Application): `<source_root>/Order/Application/CommandHandler/PlaceOrderHandler.php`

### Adding a New Feature to Existing Context

Adding "change email" feature to Customer:

```text
<architecture.source_root>/Customer/
├── Application/
│   ├── Command/
│   │   └── ChangeCustomerEmailCommand.php     # NEW
│   └── CommandHandler/
│       └── ChangeCustomerEmailHandler.php     # NEW
└── Domain/
    ├── Entity/
    │   └── Customer.php                        # ADD method: changeEmail()
    └── Event/
        └── CustomerEmailChanged.php            # NEW
```

## Anti-Pattern: Wrong File Placement

### WRONG: Business logic in Infrastructure

```text
<source_root>/Customer/Infrastructure/Validator/CustomerEmailRules.php
// Business validation should be in Domain (Value Objects)
```

**Fix**: Move to `<source_root>/Customer/Domain/ValueObject/Email.php`

### WRONG: Framework code in Domain

```text
<source_root>/Customer/Domain/Entity/Customer.php
use Doctrine\ORM\Mapping as ORM;   // or ODM annotations — same violation
```

**Fix**: Use XML mappings in `config/doctrine/Customer.<mapper-suffix>.xml`
(suffix per `persistence.mapper`)

### WRONG: Use case logic in Entity

```text
<source_root>/Customer/Domain/Entity/Customer.php
public function sendWelcomeEmail() // Application concern!
```

**Fix**: Move to
`<source_root>/Customer/Application/EventSubscriber/SendWelcomeEmailOnCustomerCreated.php`

## Quick Checks

Before committing new files:

```bash
# Verify architecture: run the target mapped by make.deptrac
# (must report quality.deptrac_violations = 0)

# Check no framework imports in Domain (generic tooling)
grep -r "use Symfony\|use Doctrine\|use ApiPlatform" <architecture.source_root>/*/Domain/

# Ensure handlers are registered
grep -r "implements CommandHandlerInterface" <architecture.source_root>/*/Application/CommandHandler/
```

## Related Skills

- [deptrac-fixer](../deptrac-fixer/SKILL.md) - Fix violations when files are in wrong layers
- [implementing-ddd-architecture](../implementing-ddd-architecture/SKILL.md) - DDD patterns behind this layout
- [quality-standards](../quality-standards/SKILL.md) - Maintain code quality standards

---

**Remember**: Structure reflects intent. Proper file placement makes the
architecture self-documenting.
