# DDD Architecture Reference Guide

**Detailed patterns, workflows, and implementation guidelines for Domain-Driven Design architecture.**

> Persistence examples branch on the project profile. `persistence.mapper`
> selects the Doctrine API: `doctrine-orm` → `EntityManagerInterface` with
> `.orm.xml` mappings; `doctrine-odm` → `DocumentManager` with
> `.mongodb.xml` mappings. `persistence.engine` names the backing store
> (`mysql` | `mariadb` | `postgresql` | `mongodb`). Apply the variant your
> profile declares. Context names in examples (`Customer`, `Catalog`) are
> placeholders for entries in `architecture.bounded_contexts` under
> `architecture.source_root`.

This document provides comprehensive explanations and step-by-step workflows referenced from [SKILL.md](SKILL.md).

## Table of Contents

- [Layer Responsibilities](#layer-responsibilities)
- [Creating a New Entity](#creating-a-new-entity)
- [Fixing Deptrac Violations](#fixing-deptrac-violations)
- [Doctrine Configuration](#doctrine-configuration)
- [Event-Driven Architecture Details](#event-driven-architecture-details)
- [Repository Pattern Details](#repository-pattern-details)
- [Factory Pattern for Entity Creation](#factory-pattern-for-entity-creation)
- [When to Use Value Objects (Pragmatic Approach)](#when-to-use-value-objects-pragmatic-approach)
- [Anti-Patterns Deep Dive](#anti-patterns-deep-dive)

---

## Layer Responsibilities

### Domain Layer: Pure Business Logic

**Purpose**: Encapsulate core business logic and business rules.

**Allowed Dependencies**: NONE (pure PHP only)

**Contains**:

- **Entities**: Objects with identity (e.g., `Customer`, `Product`, `Order`)
- **Value Objects**: Immutable objects without identity (e.g., `Email`, `Money`, `Address`)
- **Aggregates**: Clusters of entities treated as a single unit (extend `AggregateRoot`)
- **Domain Events**: Interfaces representing business events (e.g., `CustomerCreated`, `OrderPlaced`)
- **Repository Interfaces**: Contracts for data persistence
- **Domain Exceptions**: Business rule violations (e.g., `InvalidEmailException`)
- **Factory Interfaces**: Complex object creation contracts

**Strict Rules**:

- ❌ NO framework components (`Symfony\*`)
- ❌ NO Doctrine annotations/attributes (`Doctrine\*`)
- ❌ NO API Platform decorators (`ApiPlatform\*`)
- ❌ NO framework-specific code
- ❌ NO persistence concerns
- ❌ NO HTTP/API concerns
- ✅ Pure business logic ONLY

**Example Domain Entity**:

```php
// <architecture.source_root>/Customer/Domain/Entity/Customer.php
namespace App\Customer\Domain\Entity;

use App\Shared\Domain\Aggregate\AggregateRoot;
use App\Customer\Domain\ValueObject\Email;
use App\Customer\Domain\Event\CustomerCreated;

class Customer extends AggregateRoot
{
    private Ulid $id;
    private Email $email;
    private string $name;

    public function __construct(Ulid $id, Email $email, string $name)
    {
        $this->id = $id;
        $this->email = $email;
        $this->ensureNameIsValid($name);
        $this->name = $name;

        // Record domain event
        $this->record(new CustomerCreated($this->id, $this->email));
    }

    public function changeName(string $newName): void
    {
        $this->ensureNameIsValid($newName);
        $this->name = $newName;
    }

    private function ensureNameIsValid(string $name): void
    {
        if (empty(trim($name))) {
            throw new InvalidCustomerNameException(
                "Customer name cannot be empty"
            );
        }
    }

    // Pure getters, no business logic in getters
    public function id(): Ulid { return $this->id; }
    public function email(): Email { return $this->email; }
    public function name(): string { return $this->name; }
}
```

> The `App\Shared\` namespace stands for the shared kernel declared by
> `architecture.shared_context` (skip shared-kernel imports when the
> profile declares `null`).

### Application Layer: Use Case Orchestration

**Purpose**: Orchestrate use cases and coordinate between Domain and Infrastructure.

**Allowed Dependencies**: Domain, Infrastructure, framework components,
API Platform (when `framework.api_platform` is set), GraphQL (when
`framework.graphql` is true), Logging

**Contains**:

- **Command Handlers**: Execute write operations (implement `CommandHandlerInterface`)
- **Event Subscribers**: React to domain events (implement `DomainEventSubscriberInterface`)
- **DTOs**: Data transfer between layers (validation via YAML config at `config/validator/`)
- **Transformers**: Convert between representations
- **API Platform Processors**: Handle API operations (when `framework.api_platform` is set)
- **GraphQL Resolvers**: Handle GraphQL queries/mutations (when `framework.graphql` is true)
- **Message Handlers**: Process async messages
- **Factory Implementations**: Build domain objects from external data

**Rules**:

- ❌ NO business logic (delegate to Domain)
- ✅ Orchestrate workflows
- ✅ Transform data between layers
- ✅ Handle application-level concerns (validation, transformation)
- ✅ Use dependency injection

**Example Command Handler**:

```php
// <architecture.source_root>/Customer/Application/CommandHandler/CreateCustomerHandler.php
namespace App\Customer\Application\CommandHandler;

use App\Customer\Application\Command\CreateCustomerCommand;
use App\Customer\Domain\Entity\Customer;
use App\Customer\Domain\Repository\CustomerRepositoryInterface;
use App\Customer\Domain\ValueObject\Email;
use App\Shared\Domain\Bus\Command\CommandHandlerInterface;

final readonly class CreateCustomerHandler implements CommandHandlerInterface
{
    public function __construct(
        private CustomerRepositoryInterface $repository,
        private CustomerFactoryInterface $customerFactory  // ✅ Inject factory
    ) {}

    public function __invoke(CreateCustomerCommand $command): void
    {
        // Transform primitive data to domain value objects
        $email = new Email($command->email);

        // ✅ Use factory instead of 'new' for entity creation
        // Factory encapsulates construction logic and improves testability
        $customer = $this->customerFactory->create(
            $command->id,
            $email,
            $command->name
        );

        // Persist - infrastructure concern
        $this->repository->save($customer);

        // Domain events are automatically dispatched after flush
    }
}
```

### Infrastructure Layer: Technical Implementation

**Purpose**: Implement technical details and external integrations.

**Allowed Dependencies**: Domain, Application, framework, Doctrine
(ORM or ODM per `persistence.mapper`), Logging

**Contains**:

- **Repository Implementations**: Concrete persistence logic for the mapper declared by `persistence.mapper`
- **Message Bus Implementations**: Command/Event bus (e.g., Symfony Messenger)
- **Doctrine Types**: Custom database types (e.g., `UlidType`)
- **External Service Integrations**: APIs, message queues, email services
- **Event Listeners**: Doctrine lifecycle listeners
- **Retry Strategies**: For message handling

**Rules**:

- ✅ Implement interfaces from Domain
- ✅ Handle persistence details
- ✅ Manage external communications
- ❌ NO business logic

**Example Repository Implementation** (`persistence.mapper: doctrine-orm`):

```php
// <architecture.source_root>/Customer/Infrastructure/Repository/CustomerRepository.php
namespace App\Customer\Infrastructure\Repository;

use App\Customer\Domain\Entity\Customer;
use App\Customer\Domain\Repository\CustomerRepositoryInterface;
use App\Shared\Domain\ValueObject\Ulid;
use Doctrine\ORM\EntityManagerInterface;

final class CustomerRepository implements CustomerRepositoryInterface
{
    public function __construct(
        private EntityManagerInterface $entityManager
    ) {}

    public function save(Customer $customer): void
    {
        $this->entityManager->persist($customer);
        $this->entityManager->flush();
        // Domain events are dispatched via Doctrine listeners after flush
    }

    public function findById(Ulid $id): ?Customer
    {
        return $this->entityManager->find(Customer::class, $id);
    }
}
```

**Variant** (`persistence.mapper: doctrine-odm`): inject
`Doctrine\ODM\MongoDB\DocumentManager` instead of
`EntityManagerInterface`; the `persist`/`flush`/`find` call shape is
identical.

---

## Creating a New Entity

**Complete workflow for adding a new entity to the system.**

### Step 1: Identify Bounded Context

**Questions to answer**:

- Does this entity belong to an existing context (one of `architecture.bounded_contexts`)?
- Or do you need to create a new bounded context?
- What is the business domain for this entity?

**Example**: Adding a `Product` entity → belongs in a `Catalog` context

### Step 2: Design Domain Model (Domain Layer)

**Location**: `<architecture.source_root>/{Context}/Domain/Entity/{Entity}.php`

**Tasks**:

1. Create the entity class
2. Identify Value Objects needed (e.g., `Money`, `ProductName`)
3. Define business rules and invariants
4. Decide if it's an Aggregate Root (extends `AggregateRoot`)
5. Design business methods (not setters!)

**Example**:

```php
// <architecture.source_root>/Catalog/Domain/Entity/Product.php
namespace App\Catalog\Domain\Entity;

use App\Catalog\Domain\ValueObject\Money;
use App\Catalog\Domain\ValueObject\ProductName;
use App\Catalog\Domain\Event\ProductCreated;
use App\Shared\Domain\Aggregate\AggregateRoot;
use App\Shared\Domain\ValueObject\Ulid;

class Product extends AggregateRoot
{
    private Ulid $id;
    private ProductName $name;
    private Money $price;
    private \DateTimeImmutable $createdAt;

    private function __construct(
        Ulid $id,
        ProductName $name,
        Money $price,
        \DateTimeImmutable $createdAt
    ) {
        $this->id = $id;
        $this->name = $name;
        $this->price = $price;
        $this->createdAt = $createdAt;
    }

    // Named constructor - expresses intent
    public static function create(Ulid $id, ProductName $name, Money $price): self
    {
        $product = new self($id, $name, $price, new \DateTimeImmutable());
        $product->record(new ProductCreated($product->id, $product->name, $product->price));
        return $product;
    }

    // Business method - not a setter
    public function changePrice(Money $newPrice): void
    {
        if ($newPrice->isNegative()) {
            throw new InvalidProductPriceException("Price cannot be negative");
        }

        $this->price = $newPrice;
        $this->record(new ProductPriceChanged($this->id, $newPrice));
    }

    // Getters
    public function id(): Ulid { return $this->id; }
    public function name(): ProductName { return $this->name; }
    public function price(): Money { return $this->price; }
}
```

### Step 3: Define Repository Interface (Domain Layer)

**Location**: `<architecture.source_root>/{Context}/Domain/Repository/{Entity}RepositoryInterface.php`

**Tasks**:

1. Define `save()` method
2. Define `findById()` method
3. Add custom finders as needed (e.g., `findByName()`, `findByCriteria()`)

**Example**:

```php
// <architecture.source_root>/Catalog/Domain/Repository/ProductRepositoryInterface.php
namespace App\Catalog\Domain\Repository;

use App\Catalog\Domain\Entity\Product;
use App\Shared\Domain\ValueObject\Ulid;

interface ProductRepositoryInterface
{
    public function save(Product $product): void;

    public function findById(Ulid $id): ?Product;

    public function findByName(ProductName $name): ?Product;
}
```

### Step 4: Create Doctrine Mapping (Infrastructure Config)

Keep the Domain entity attribute-free: the mapping lives in XML config,
and its dialect follows `persistence.mapper`.

**When `persistence.mapper` is `doctrine-orm`** — location:
`config/doctrine/{Entity}.orm.xml`:

```xml
<!-- config/doctrine/Product.orm.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<doctrine-mapping xmlns="http://doctrine-project.org/schemas/orm/doctrine-mapping">
    <entity name="App\Catalog\Domain\Entity\Product" table="products">
        <id name="id" type="ulid">
            <generator strategy="NONE"/>
        </id>
        <field name="name" type="string"/>
        <embedded name="price" class="App\Catalog\Domain\ValueObject\Money"/>
        <field name="createdAt" type="datetime_immutable"/>
    </entity>
</doctrine-mapping>
```

**When `persistence.mapper` is `doctrine-odm`** — location:
`config/doctrine/{Entity}.mongodb.xml`:

```xml
<!-- config/doctrine/Product.mongodb.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<doctrine-mongo-mapping xmlns="http://doctrine-project.org/schemas/odm/doctrine-mongo-mapping">
    <document name="App\Catalog\Domain\Entity\Product" collection="products">
        <field name="id" type="ulid" id="true" strategy="NONE"/>
        <field name="name" type="string"/>
        <embed-one target-document="App\Catalog\Domain\ValueObject\Money" field="price"/>
        <field name="createdAt" type="date_immutable"/>
    </document>
</doctrine-mongo-mapping>
```

**Tasks** (either dialect):

1. Create the XML mapping file
2. Map entity fields to the table (`persistence.engine` `mysql`/`mariadb`/`postgresql`) or collection (`mongodb`)
3. Map Value Object embeds
4. Define ID strategy

### Step 5: Implement Repository (Infrastructure Layer)

**Location**: `<architecture.source_root>/{Context}/Infrastructure/Repository/{Entity}Repository.php`

**Tasks**:

1. Implement the repository interface
2. Inject the Doctrine manager for your `persistence.mapper` (`EntityManagerInterface` or `DocumentManager`)
3. Implement persistence methods

**Example** (`persistence.mapper: doctrine-orm`):

```php
// <architecture.source_root>/Catalog/Infrastructure/Repository/ProductRepository.php
namespace App\Catalog\Infrastructure\Repository;

use App\Catalog\Domain\Entity\Product;
use App\Catalog\Domain\Repository\ProductRepositoryInterface;
use Doctrine\ORM\EntityManagerInterface;

final class ProductRepository implements ProductRepositoryInterface
{
    public function __construct(private EntityManagerInterface $em) {}

    public function save(Product $product): void
    {
        $this->em->persist($product);
        $this->em->flush();
    }

    public function findById(Ulid $id): ?Product
    {
        return $this->em->find(Product::class, $id);
    }
}
```

For `doctrine-odm`, swap `EntityManagerInterface` for `DocumentManager`
(`Doctrine\ODM\MongoDB\DocumentManager`) — the method bodies are unchanged.

### Step 6: Create Commands (Application Layer)

**Location**: `<architecture.source_root>/{Context}/Application/Command/{Action}{Entity}Command.php`

**Tasks**:

1. Create command implementing `CommandInterface`
2. Make it readonly and immutable
3. Use primitive types or Ulid for properties

**Example**:

```php
// <architecture.source_root>/Catalog/Application/Command/CreateProductCommand.php
namespace App\Catalog\Application\Command;

use App\Shared\Domain\Bus\Command\CommandInterface;
use App\Shared\Domain\ValueObject\Ulid;

final readonly class CreateProductCommand implements CommandInterface
{
    public function __construct(
        public Ulid $id,
        public string $name,
        public int $priceInCents,
        public string $currency
    ) {}
}
```

### Step 7: Create Command Handlers (Application Layer)

**Location**: `<architecture.source_root>/{Context}/Application/CommandHandler/{Action}{Entity}Handler.php`

**Tasks**:

1. Create handler implementing `CommandHandlerInterface`
2. Inject repository
3. Transform command data to domain objects
4. Call domain methods
5. Persist via repository

**Example** (shown above in Application Layer section)

### Step 8: Define Domain Events (Domain Layer)

**Location**: `<architecture.source_root>/{Context}/Domain/Event/{Entity}{Action}.php`

**Example**:

```php
// <architecture.source_root>/Catalog/Domain/Event/ProductCreated.php
namespace App\Catalog\Domain\Event;

use App\Shared\Domain\Bus\Event\DomainEvent;

final readonly class ProductCreated extends DomainEvent
{
    public function __construct(
        public Ulid $productId,
        public ProductName $name,
        public Money $price,
        ?string $eventId = null,
        ?string $occurredOn = null
    ) {
        parent::__construct($eventId, $occurredOn);
    }

    public static function eventName(): string
    {
        return 'product.created';
    }
}
```

### Step 9: Create Event Subscribers (Application Layer)

**Location**: `<architecture.source_root>/{Context}/Application/EventSubscriber/{Action}On{Event}.php`

**Example**:

```php
// <architecture.source_root>/Catalog/Application/EventSubscriber/NotifyWarehouseOnProductCreated.php
namespace App\Catalog\Application\EventSubscriber;

use App\Shared\Domain\Bus\Event\DomainEventSubscriberInterface;

final readonly class NotifyWarehouseOnProductCreated implements DomainEventSubscriberInterface
{
    public function __construct(
        private WarehouseNotifierInterface $warehouseNotifier
    ) {}

    public static function subscribedTo(): array
    {
        return [ProductCreated::class];
    }

    public function __invoke(ProductCreated $event): void
    {
        $this->warehouseNotifier->notifyNewProduct($event->productId);
    }
}
```

### Step 10: Verify Architecture

**Run Deptrac**: the target mapped by `make.deptrac` (if the mapping is
`null`, the capability is absent — note it and verify layer rules by
review).

**Expected**: Zero violations (`quality.deptrac_violations` ships at `0`
and is a fixed ceiling — it may never be raised; score thresholds
elsewhere are raise-only floors). If violations exist, fix the code
(never change `deptrac.yaml`).

**Run Tests**: the target mapped by `make.tests`.

---

## Fixing Deptrac Violations

**Complete guide to diagnosing and fixing architectural violations.**

### Violation Process

1. **Run Deptrac**: the target mapped by `make.deptrac`
2. **Read Output Carefully**: Understand what's wrong
3. **Identify Problem**: Which layer, which dependency?
4. **Plan Refactor**: How to fix the architecture?
5. **Implement Fix**: Move/refactor code
6. **Verify**: Re-run the target mapped by `make.deptrac`

### Common Violation Patterns

#### Violation Type 1: Domain → Framework (Validators)

**Symptom**:

```text
Domain must not depend on Symfony
<architecture.source_root>/Customer/Domain/Entity/Customer.php:15
  uses Symfony\Component\Validator\Constraints as Assert
```

**Problem Code**:

```php
namespace App\Customer\Domain\Entity;

use Symfony\Component\Validator\Constraints as Assert;

class Customer
{
    #[Assert\Email]
    private string $email;

    #[Assert\NotBlank]
    private string $name;
}
```

**Solution**: Extract validation to Value Objects

```php
// Domain entity
namespace App\Customer\Domain\Entity;

use App\Customer\Domain\ValueObject\Email;

class Customer
{
    private Email $email; // Value Object validates itself
    private string $name;

    public function __construct(Email $email, string $name)
    {
        $this->email = $email;
        $this->ensureNameIsValid($name);
        $this->name = $name;
    }

    private function ensureNameIsValid(string $name): void
    {
        if (empty(trim($name))) {
            throw new InvalidCustomerNameException();
        }
    }
}

```

**For API input validation**, use YAML config in Application layer:

```php
// Application/DTO/CreateCustomerDTO.php
namespace App\Customer\Application\DTO;

final class CreateCustomerDTO
{
    public string $email;
    public string $name;
}
```

```yaml
# config/validator/Customer.yaml
App\Customer\Application\DTO\CreateCustomerDTO:
  properties:
    email:
      - NotBlank: { message: 'not.blank' }
      - Email: { message: 'email.invalid' }
      - App\Shared\Application\Validator\UniqueEmail: ~
    name:
      - NotBlank: { message: 'not.blank' }
      - Length:
          min: 2
          max: 100
```

#### Violation Type 2: Domain → Doctrine (Mapping Attributes)

**Symptom**:

```text
Domain must not depend on Doctrine
<architecture.source_root>/Catalog/Domain/Entity/Product.php:10
  uses Doctrine mapping attributes
```

**Problem Code** (`persistence.mapper: doctrine-orm`):

```php
namespace App\Catalog\Domain\Entity;

use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity]
#[ORM\Table(name: 'products')]
class Product
{
    #[ORM\Id]
    #[ORM\Column(type: 'ulid')]
    private Ulid $id;

    #[ORM\Column(type: 'string')]
    private string $name;
}
```

**Problem Code** (`persistence.mapper: doctrine-odm`):

```php
namespace App\Catalog\Domain\Entity;

use Doctrine\ODM\MongoDB\Mapping\Annotations as ODM;

#[ODM\Document(collection: 'products')]
class Product
{
    #[ODM\Id(type: 'ulid', strategy: 'NONE')]
    private Ulid $id;

    #[ODM\Field(type: 'string')]
    private string $name;
}
```

**Solution**: Use XML mappings (dialect per `persistence.mapper`, see
[Doctrine Configuration](#doctrine-configuration))

```php
// Pure domain entity (NO Doctrine imports)
namespace App\Catalog\Domain\Entity;

class Product
{
    private Ulid $id;
    private string $name;

    // Pure business logic
}
```

#### Violation Type 3: Domain → API Platform (Attributes)

Applies when `framework.api_platform` is set.

**Symptom**:

```text
Domain must not depend on ApiPlatform
<architecture.source_root>/Customer/Domain/Entity/Customer.php:8
  uses ApiPlatform\Metadata\ApiResource
```

**Problem Code**:

```php
namespace App\Customer\Domain\Entity;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;

#[ApiResource(operations: [new Get()])]
class Customer
{
    private Ulid $id;
}
```

**Solution Option 1**: Configure in YAML

```php
// Pure domain entity
namespace App\Customer\Domain\Entity;

class Customer
{
    private Ulid $id;
}
```

```yaml
# config/packages/api_platform.yaml
resources:
  App\Customer\Domain\Entity\Customer:
    operations:
      get:
        method: GET
```

**Solution Option 2**: Use DTOs in Application layer

```php
// Application/DTO/CustomerDTO.php
namespace App\Customer\Application\DTO;

use ApiPlatform\Metadata\ApiResource;

#[ApiResource(operations: [...])]
final class CustomerDTO
{
    public string $id;
    public string $name;
}
```

#### Violation Type 4: Infrastructure → Application (Handler)

**Symptom**:

```text
Infrastructure must not depend on Application (Command Handler)
<architecture.source_root>/Customer/Infrastructure/EventListener/CustomerListener.php:25
```

**Problem Code**:

```php
namespace App\Customer\Infrastructure\EventListener;

use App\Customer\Application\CommandHandler\SendWelcomeEmailHandler;

class CustomerListener
{
    public function __construct(
        private SendWelcomeEmailHandler $handler // Direct dependency!
    ) {}

    public function postPersist(LifecycleEventArgs $args): void
    {
        ($this->handler)(new SendWelcomeEmailCommand(...));
    }
}
```

**Solution**: Use Command Bus

```php
namespace App\Customer\Infrastructure\EventListener;

use App\Shared\Domain\Bus\Command\CommandBusInterface;

class CustomerListener
{
    public function __construct(
        private CommandBusInterface $commandBus // Use bus instead
    ) {}

    public function postPersist(LifecycleEventArgs $args): void
    {
        $this->commandBus->dispatch(new SendWelcomeEmailCommand(...));
    }
}
```

**Better Solution**: Use Domain Events

```php
// Domain entity records event
class Customer extends AggregateRoot
{
    public function __construct(...)
    {
        // ...
        $this->record(new CustomerCreated($this->id));
    }
}

// Application subscriber reacts
class SendWelcomeEmailOnCustomerCreated implements DomainEventSubscriberInterface
{
    public static function subscribedTo(): array
    {
        return [CustomerCreated::class];
    }

    public function __invoke(CustomerCreated $event): void
    {
        // Send email
    }
}
```

---

## Doctrine Configuration

The mapping dialect, file suffix, base `Type` class, and registration key
all follow `persistence.mapper`.

### XML Mapping Structure — `doctrine-orm`

**Location**: `config/doctrine/{EntityName}.orm.xml`

**Basic Template**:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<doctrine-mapping xmlns="http://doctrine-project.org/schemas/orm/doctrine-mapping"
                  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                  xsi:schemaLocation="http://doctrine-project.org/schemas/orm/doctrine-mapping
                  https://www.doctrine-project.org/schemas/orm/doctrine-mapping.xsd">

    <entity name="App\{Context}\Domain\Entity\{Entity}" table="{table_name}">
        <!-- ID field -->
        <id name="id" type="ulid">
            <generator strategy="NONE"/>
        </id>

        <!-- Simple fields -->
        <field name="name" type="string"/>
        <field name="createdAt" type="datetime_immutable"/>

        <!-- Embedded Value Objects -->
        <embedded name="email" class="App\{Context}\Domain\ValueObject\Email"/>

        <!-- Associations -->
        <many-to-one field="other" target-entity="App\{OtherContext}\Domain\Entity\Other"/>
    </entity>
</doctrine-mapping>
```

### XML Mapping Structure — `doctrine-odm`

**Location**: `config/doctrine/{EntityName}.mongodb.xml`

**Basic Template**:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<doctrine-mongo-mapping xmlns="http://doctrine-project.org/schemas/odm/doctrine-mongo-mapping"
                        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                        xsi:schemaLocation="http://doctrine-project.org/schemas/odm/doctrine-mongo-mapping
                        https://www.doctrine-project.org/schemas/odm/doctrine-mongo-mapping.xsd">

    <document name="App\{Context}\Domain\Entity\{Entity}" collection="{collection_name}">
        <!-- ID field -->
        <field name="id" type="ulid" id="true" strategy="NONE"/>

        <!-- Simple fields -->
        <field name="name" type="string"/>
        <field name="createdAt" type="date_immutable"/>

        <!-- Embedded Value Objects -->
        <embed-one target-document="App\{Context}\Domain\ValueObject\Email" field="email"/>

        <!-- References -->
        <reference-one target-document="App\{OtherContext}\Domain\Entity\Other" field="other"/>
    </document>
</doctrine-mongo-mapping>
```

### Custom Doctrine Types

**Location**: `<architecture.source_root>/<architecture.shared_context>/Infrastructure/DoctrineType/`
(or the context's own `Infrastructure/DoctrineType/` when no shared kernel is declared)

**Example: Ulid Type** (`persistence.mapper: doctrine-orm`, extends the DBAL type):

```php
namespace App\Shared\Infrastructure\DoctrineType;

use Doctrine\DBAL\Platforms\AbstractPlatform;
use Doctrine\DBAL\Types\Type;
use Symfony\Component\Uid\Ulid;

final class UlidType extends Type
{
    public function convertToPHPValue($value, AbstractPlatform $platform): Ulid
    {
        return Ulid::fromString($value);
    }

    public function convertToDatabaseValue($value, AbstractPlatform $platform): string
    {
        return (string) $value;
    }
}
```

**Example: Ulid Type** (`persistence.mapper: doctrine-odm`, extends the ODM type):

```php
namespace App\Shared\Infrastructure\DoctrineType;

use Doctrine\ODM\MongoDB\Types\Type;
use Symfony\Component\Uid\Ulid;

final class UlidType extends Type
{
    public function convertToPHPValue($value): Ulid
    {
        return Ulid::fromString($value);
    }

    public function convertToDatabaseValue($value): string
    {
        return (string) $value;
    }
}
```

**Register** — `doctrine-orm` in `config/packages/doctrine.yaml`:

```yaml
doctrine:
  dbal:
    types:
      ulid: App\Shared\Infrastructure\DoctrineType\UlidType
```

**Register** — `doctrine-odm` in `config/packages/doctrine_mongodb.yaml`:

```yaml
doctrine_mongodb:
  types:
    ulid: App\Shared\Infrastructure\DoctrineType\UlidType
```

---

## Event-Driven Architecture Details

### Domain Event Structure

Domain events extend a `DomainEvent` base class:

```php
namespace App\Shared\Domain\Bus\Event;

abstract readonly class DomainEvent
{
    private string $eventId;
    private string $occurredOn;

    public function __construct(?string $eventId = null, ?string $occurredOn = null)
    {
        $this->eventId = $eventId ?? Ulid::random()->toString();
        $this->occurredOn = $occurredOn ?? (new \DateTimeImmutable())->format('Y-m-d H:i:s');
    }

    abstract public static function eventName(): string;

    public function eventId(): string { return $this->eventId; }
    public function occurredOn(): string { return $this->occurredOn; }
}
```

### Event Subscriber Auto-Registration

**In `config/services.yaml`**:

```yaml
_instanceof:
  App\Shared\Domain\Bus\Event\DomainEventSubscriberInterface:
    tags: ['app.event_subscriber']

App\Shared\Infrastructure\Bus\Event\EventBusFactory:
  arguments:
    - !tagged_iterator app.event_subscriber
```

### Event Dispatching Flow

1. Domain entity records event: `$this->record($event)`
2. Event stored in aggregate: `$this->domainEvents[]`
3. Handler calls repository: `$repository->save($entity)`
4. Repository persists: the Doctrine manager's `flush()` (`EntityManagerInterface` or `DocumentManager` per `persistence.mapper`)
5. Infrastructure listener pulls events: `$entity->pullDomainEvents()`
6. Events dispatched to subscribers via the message bus (e.g., Symfony Messenger)

---

## Repository Pattern Details

### Repository Method Naming

Use consistent, descriptive names:

- `save(Entity $entity): void` - Persist (create/update)
- `findById(Ulid $id): ?Entity` - Find by ID, nullable
- `findByEmail(Email $email): ?Entity` - Find by value object
- `findAll(): array` - Get all entities
- `findByCriteria(Criteria $criteria): Collection` - Complex queries
- `delete(Entity $entity): void` - Remove entity

### Criteria Pattern

For complex queries, use Specification/Criteria pattern. The criteria
object stays storage-agnostic in Domain; translating its filters into the
actual query language (SQL for `mysql`/`mariadb`/`postgresql`, query
operators for `mongodb` — per `persistence.engine`) is an Infrastructure
concern inside the repository implementation:

```php
interface ProductRepositoryInterface
{
    public function findByCriteria(Criteria $criteria): ProductCollection;
}

// Usage
$criteria = new Criteria(
    filters: ['status' => 'published', 'minPrice' => 1000],
    orderBy: ['createdAt' => 'DESC'],
    limit: 10
);

$products = $repository->findByCriteria($criteria);
```

---

## Factory Pattern for Entity Creation

### Why Use Factories?

**Key Principle**: In production code, prefer **Factory classes with interfaces** over direct `new` keyword or static factory methods for creating domain entities and complex value objects.

**Benefits**:

- ✅ **Single Responsibility**: Factory encapsulates object creation logic
- ✅ **Testability**: Easy to mock factories in unit tests
- ✅ **Flexibility**: Can change construction logic without modifying handlers
- ✅ **DDD Pattern**: Separates creation concerns from business logic
- ✅ **Dependency Injection**: Follows SOLID principles with interfaces

**When to Use Factories**:

- Creating domain entities (aggregates)
- Complex value objects with dependencies
- Objects requiring multi-step construction
- When you need to test creation logic separately

**When NOT to Use Factories**:

- ✅ In **tests**: Use `new` directly for simplicity
- ✅ Simple value objects without dependencies (e.g., `new Email($value)`)
- ✅ Inside factory classes themselves (the factory encapsulates `new`)

### Factory Interface

**Location**: `<architecture.source_root>/{Context}/Domain/Factory/{Entity}FactoryInterface.php`

```php
<?php

declare(strict_types=1);

namespace App\Customer\Domain\Factory;

use App\Customer\Domain\Entity\Customer;
use App\Customer\Domain\ValueObject\Email;
use App\Customer\Domain\ValueObject\CustomerName;
use App\Shared\Domain\ValueObject\Ulid;

interface CustomerFactoryInterface
{
    public function create(
        Ulid $id,
        Email $email,
        CustomerName $name
    ): Customer;
}
```

### Factory Implementation

**Location**: `<architecture.source_root>/{Context}/Domain/Factory/{Entity}Factory.php`

```php
<?php

declare(strict_types=1);

namespace App\Customer\Domain\Factory;

use App\Customer\Domain\Entity\Customer;
use App\Customer\Domain\ValueObject\Email;
use App\Customer\Domain\ValueObject\CustomerName;
use App\Shared\Domain\ValueObject\Ulid;

final readonly class CustomerFactory implements CustomerFactoryInterface
{
    public function create(
        Ulid $id,
        Email $email,
        CustomerName $name
    ): Customer {
        // Factory encapsulates the 'new' keyword
        // This is the ONLY place where we use 'new Customer()'
        return new Customer($id, $email, $name);
    }
}
```

### Using Factories in Command Handlers

**❌ BAD - Direct instantiation**:

```php
final readonly class CreateCustomerHandler implements CommandHandlerInterface
{
    public function __construct(
        private CustomerRepositoryInterface $repository
    ) {}

    public function __invoke(CreateCustomerCommand $command): void
    {
        // ❌ Direct use of 'new' - tightly coupled, harder to test
        $customer = new Customer(
            new Ulid($command->id),
            new Email($command->email),
            new CustomerName($command->name)
        );

        $this->repository->save($customer);
    }
}
```

**✅ GOOD - Factory injection**:

```php
final readonly class CreateCustomerHandler implements CommandHandlerInterface
{
    public function __construct(
        private CustomerRepositoryInterface $repository,
        private CustomerFactoryInterface $customerFactory  // ✅ Inject factory
    ) {}

    public function __invoke(CreateCustomerCommand $command): void
    {
        // ✅ Use factory - decoupled, easy to test and modify
        $customer = $this->customerFactory->create(
            new Ulid($command->id),
            new Email($command->email),
            new CustomerName($command->name)
        );

        $this->repository->save($customer);
    }
}
```

### Auto-Registration

Factories are automatically registered in `config/services.yaml`:

```yaml
services:
  _defaults:
    autowire: true
    autoconfigure: true

  # All factories under the source root are auto-registered
  App\:
    resource: '../src/'
    exclude:
      - '../src/*/Domain/Entity/'
```

(Adjust `../src/` to match `architecture.source_root`.)

### Testing with Factories

**Production code**: Use factories

```php
final readonly class CreateCustomerHandler implements CommandHandlerInterface
{
    public function __construct(
        private CustomerFactoryInterface $customerFactory
    ) {}

    public function __invoke(CreateCustomerCommand $command): void
    {
        $customer = $this->customerFactory->create(...);
        // ...
    }
}
```

**Test code**: Use `new` directly for simplicity

```php
final class CustomerRepositoryTest extends TestCase
{
    public function testSaveAndRetrieveCustomer(): void
    {
        // ✅ In tests, using 'new' is acceptable for simplicity
        $customer = new Customer(
            new Ulid('01234567-89ab-cdef-0123-456789abcdef'),
            new Email('test@example.com'),
            new CustomerName('John Doe')
        );

        $this->repository->save($customer);
        $retrieved = $this->repository->findById($customer->id());

        self::assertEquals($customer->id(), $retrieved->id());
    }
}
```

### Complex Factory Example

For entities with dependencies or complex setup:

```php
final readonly class OrderFactory implements OrderFactoryInterface
{
    public function __construct(
        private UlidFactoryInterface $ulidFactory,
        private ClockInterface $clock
    ) {}

    public function create(
        CustomerId $customerId,
        array $items,
        ShippingAddress $shippingAddress
    ): Order {
        $orderId = $this->ulidFactory->create();
        $createdAt = $this->clock->now();

        // Complex initialization logic encapsulated in factory
        $order = new Order($orderId, $customerId, $createdAt);

        foreach ($items as $item) {
            $order->addItem($item);
        }

        $order->setShippingAddress($shippingAddress);

        return $order;
    }
}
```

---

## When to Use Value Objects (Pragmatic Approach)

### Decision Criteria

**IMPORTANT**: Not every field needs to be a Value Object! Be pragmatic and consider the trade-offs.

#### ✅ When to CREATE Value Objects

1. **Complex Validation Rules**

   - Example: `Email` with format validation
   - Example: `Money` with currency and amount validation
   - Example: `PhoneNumber` with international format handling

2. **Domain-Specific Behavior**

   - Example: `Money::add()`, `Money::multiply()`
   - Example: `Address::isSameCountry()`
   - Example: `DateRange::overlaps()`

3. **Shared Across Multiple Entities**

   - Example: `Money` used in Order, Invoice, Payment
   - Example: `Address` used in Customer, Warehouse, Supplier

4. **Immutability is Critical**

   - Example: `OrderId`, `CustomerId` (identity values)
   - Example: `EmailAddress` (shouldn't change after validation)

5. **Special Domain Concept**
   - Example: `ULID` (custom ID strategy)
   - Example: `Percentage` (0-100 with business rules)
   - Example: `Temperature` (with unit conversions)

#### ❌ When NOT to Create Value Objects

1. **Simple String Fields Without Validation**

   - Example: `string $leadSource` (just a label)
   - Example: `string $notes` (free text)
   - Example: `string $reference` (no validation needed)

2. **Boolean Flags**

   - Example: `bool $confirmed`
   - Example: `bool $isActive`
   - **Exception**: Use Value Object if you need more than 2 states (use enum/Value Object pattern)

3. **Simple Numeric Fields**

   - Example: `int $quantity` (if no special rules)
   - Example: `float $discount` (if just a percentage)
   - **Exception**: Use Value Object if there's validation or behavior

4. **Fields That Will Never Have Business Logic**
   - Example: `string $externalApiId` (just storage)
   - Example: `string $rawData` (pass-through data)

### Pragmatic Entity Example

#### ✅ Pragmatic Customer Entity

```php
// <architecture.source_root>/Customer/Domain/Entity/Customer.php
namespace App\Customer\Domain\Entity;

use App\Shared\Domain\ValueObject\UlidInterface;
use DateTimeImmutable;

class Customer
{
    public function __construct(
        private string $initials,           // ✅ Simple string - no VO needed
        private string $email,              // ✅ Simple string - validated elsewhere
        private string $phone,              // ✅ Simple string - no complex logic
        private string $leadSource,         // ✅ Simple label - no VO needed
        private CustomerType $type,         // ✅ Entity reference - not a VO
        private CustomerStatus $status,     // ✅ Entity reference - not a VO
        private ?bool $confirmed,           // ✅ Simple boolean - no VO needed
        private UlidInterface $ulid,        // ✅ Domain concept - VO is justified
        private DateTimeImmutable $createdAt = new DateTimeImmutable(),
        private DateTimeImmutable $updatedAt = new DateTimeImmutable(),
    ) {}
}
```

**Why this is pragmatic**:

- Uses primitives for simple fields
- Only uses Value Object for `Ulid` (special domain concept)
- Validation happens in Application layer (DTOs) or via type hints
- No unnecessary complexity

#### ❌ Over-Engineered Customer (Too Many VOs)

```php
// DON'T DO THIS - Over-engineered!
class Customer
{
    public function __construct(
        private CustomerInitials $initials,     // ❌ Overkill - just a string
        private EmailAddress $email,            // ⚠️ Only if you need validation
        private PhoneNumber $phone,             // ⚠️ Only if you need formatting
        private LeadSource $leadSource,         // ❌ Overkill - just a label
        private CustomerType $type,
        private CustomerStatus $status,
        private ConfirmationStatus $confirmed,  // ❌ Overkill - just a bool
        private CustomerId $id,
        private CreatedAt $createdAt,           // ❌ Overkill - DateTimeImmutable is fine
        private UpdatedAt $updatedAt,           // ❌ Overkill - DateTimeImmutable is fine
    ) {}
}
```

**Why this is bad**:

- Too many classes to maintain
- No actual business value added
- Harder to understand and test
- Violates YAGNI (You Aren't Gonna Need It)

### Decision Tree

```text
Does the field need complex validation?
├─ YES → Consider Value Object
└─ NO → Is there domain behavior (methods)?
    ├─ YES → Consider Value Object
    └─ NO → Is it shared across entities?
        ├─ YES → Consider Value Object
        └─ NO → Use primitive type
```

### Worked Field-by-Field Decisions

#### ✅ Good Use of Value Object: `UlidInterface`

```php
// Justified because:
// - Special ID strategy (not UUID, not auto-increment)
// - Needs conversion logic
// - Used across all entities
private UlidInterface $ulid;
```

#### ✅ Good Use of Primitive: `email`

```php
// Justified because:
// - Validation happens in DTO layer (framework validator)
// - No special domain behavior needed
// - Keep it simple
private string $email;
```

#### ✅ Good Use of Entity Reference: `CustomerType`

```php
// Justified because:
// - Has its own identity (it's an entity, not a value)
// - Stored in its own table/collection (per persistence.engine)
// - Shared across customers
private CustomerType $type;
```

### Validation Strategy

**In this architecture, validation happens at the Application layer using YAML configuration**:

#### 1. **Application Layer (DTOs)** - YAML-based framework validator

**Location**: `config/validator/Customer.yaml`

```yaml
# config/validator/Customer.yaml
App\Customer\Application\DTO\CustomerCreate:
  properties:
    initials:
      - NotBlank: { message: 'not.blank' }
      - Length:
          max: 255
      - App\Shared\Application\Validator\Initials: ~
    email:
      - NotBlank: { message: 'not.blank' }
      - Email: { message: 'email.invalid' }
      - Length:
          max: 255
      - App\Shared\Application\Validator\UniqueEmail: ~
    phone:
      - NotBlank: { message: 'not.blank' }
      - Length:
          max: 255
    confirmed:
      - Type: { type: 'bool', message: 'This value should be a boolean.' }
```

**DTO Class** (simple properties, no annotations):

```php
// <architecture.source_root>/Customer/Application/DTO/CustomerCreate.php
namespace App\Customer\Application\DTO;

final class CustomerCreate
{
    public string $initials;
    public string $email;
    public string $phone;
    public string $leadSource;
    public string $type;
    public string $status;
    public bool $confirmed;
}
```

**Custom Validators** (when needed):

```php
// <architecture.source_root>/Shared/Application/Validator/UniqueEmail.php
namespace App\Shared\Application\Validator;

use Symfony\Component\Validator\Constraint;

#[\Attribute]
final class UniqueEmail extends Constraint
{
    public string $message = 'email.already.exists';
}
```

#### 2. **Domain Layer (Entities)** - Simple primitives, no validation

```php
// <architecture.source_root>/Customer/Domain/Entity/Customer.php
class Customer
{
    public function __construct(
        private string $email,  // No validation here!
        private string $phone,  // Validation already done in DTO
        // ...
    ) {}

    public function update(CustomerUpdate $updateData): void
    {
        // No validation - trust the input has been validated
        $this->email = $updateData->newEmail;
        $this->phone = $updateData->newPhone;
        $this->updatedAt = new DateTimeImmutable();
    }
}
```

#### 3. **Domain Layer (Entity Methods)** - Business invariants only

```php
// Only validate business rules, not input format
public function changeStatus(CustomerStatus $newStatus): void
{
    // Business rule: can't change status if customer is deleted
    if ($this->isDeleted()) {
        throw new CannotChangeStatusOfDeletedCustomerException();
    }

    $this->status = $newStatus;
    $this->updatedAt = new DateTimeImmutable();
}
```

### Key Differences from "Pure" DDD

**A pragmatic codebase following this style does NOT:**

- ❌ Use Value Objects with validation in constructors
- ❌ Use annotation-based validation on DTOs
- ❌ Validate format/structure in domain entities

**It DOES:**

- ✅ Use YAML configuration for all validation rules
- ✅ Keep domain entities simple with primitives
- ✅ Validate at the Application boundary (DTOs)
- ✅ Use custom validators for business validation (`UniqueEmail`)
- ✅ Only enforce business invariants in domain methods

### Summary: Be Pragmatic

✅ **DO**:

- Use primitives by default
- Add Value Objects when you need validation + behavior
- Follow the patterns already established in the codebase
- Keep it simple (YAGNI principle)

❌ **DON'T**:

- Wrap every field in a Value Object "because DDD says so"
- Create Value Objects without clear benefit
- Add complexity for theoretical future needs
- Ignore the existing codebase patterns

**Remember**: The goal is **maintainable, understandable code**, not "pure" DDD at all costs.

---

## Anti-Patterns Deep Dive

### 1. Business Logic in Command Handlers

**Why it's wrong**: Handlers are for orchestration, not business rules.

**Example (WRONG)**:

```php
class UpdateCustomerStatusHandler
{
    public function __invoke(UpdateCustomerStatusCommand $cmd): void
    {
        $customer = $this->repository->findById($cmd->customerId);

        // Business logic in handler - WRONG!
        if ($customer->getStatus() === 'active' && $cmd->newStatus === 'active') {
            throw new CustomerAlreadyActiveException();
        }

        $customer->setStatus($cmd->newStatus);
        $this->repository->save($customer);
    }
}
```

**Correct Approach**:

```php
// Handler orchestrates
class UpdateCustomerStatusHandler
{
    public function __invoke(UpdateCustomerStatusCommand $cmd): void
    {
        $customer = $this->repository->findById($cmd->customerId);

        // Delegate to domain method
        if ($cmd->newStatus === 'active') {
            $customer->activate();
        } else {
            $customer->deactivate();
        }

        $this->repository->save($customer);
    }
}

// Domain entity contains business logic
class Customer extends AggregateRoot
{
    public function activate(): void
    {
        if ($this->status->isActive()) {
            throw new CustomerAlreadyActiveException();
        }
        $this->status = CustomerStatus::active();
        $this->record(new CustomerActivated($this->id));
    }
}
```

### 2. Anemic Domain Models

**Why it's wrong**: Domain becomes a data bag; logic scatters across handlers.

**Example (WRONG)**:

```php
class Order
{
    private array $items = [];

    public function getItems(): array { return $this->items; }
    public function setItems(array $items): void { $this->items = $items; }
}

// Business logic in handler
class AddOrderItemHandler
{
    public function __invoke(AddOrderItemCommand $cmd): void
    {
        $order = $this->repository->findById($cmd->orderId);
        $items = $order->getItems();

        // Validation in handler - WRONG
        if (count($items) >= 100) {
            throw new TooManyItemsException();
        }

        $items[] = new OrderItem($cmd->productId, $cmd->quantity);
        $order->setItems($items);
    }
}
```

**Correct Approach**:

```php
class Order extends AggregateRoot
{
    private array $items = [];

    // Business method with validation
    public function addItem(OrderItem $item): void
    {
        if (count($this->items) >= 100) {
            throw new TooManyItemsException("Order cannot have more than 100 items");
        }

        $this->items[] = $item;
        $this->record(new OrderItemAdded($this->id, $item));
    }

    public function items(): array { return $this->items; }
}

// Handler delegates
class AddOrderItemHandler
{
    public function __invoke(AddOrderItemCommand $cmd): void
    {
        $order = $this->repository->findById($cmd->orderId);
        $item = new OrderItem($cmd->productId, $cmd->quantity);

        $order->addItem($item); // Delegation

        $this->repository->save($order);
    }
}
```

### 3. Not Using Value Objects

**Why it's wrong**: Validation duplicated, primitive obsession, weak types.

**Example (WRONG)** — email accepted with no validation anywhere:

```php
class Customer
{
    private string $email;

    public function __construct(string $email)
    {
        // ❌ NO validation anywhere - not here, not in the Application layer!
        $this->email = $email;
    }

    public function changeEmail(string $newEmail): void
    {
        // ❌ NO validation anywhere!
        $this->email = $newEmail;
        $this->record(new CustomerEmailChanged($this->id, $newEmail));
    }
}
```

**Correct Approach** — keep the entity pure and validate at the Application boundary:

```php
// Domain Entity - Pure PHP, no validation
class Customer
{
    private string $email;

    public function __construct(string $email)
    {
        $this->email = $email; // ✅ No validation - handled in Application layer
    }

    public function changeEmail(string $newEmail): void
    {
        $this->email = $newEmail; // ✅ Validation already done by Application layer
        $this->record(new CustomerEmailChanged($this->id, $newEmail));
    }

    public function email(): string
    {
        return $this->email;
    }
}
```

```yaml
# config/validator/Customer.yaml - Validation in Application layer
App\Customer\Application\DTO\CustomerCreate:
  properties:
    email:
      - NotBlank: { message: 'not.blank' }
      - Email: { message: 'email.invalid' }
      - App\Shared\Application\Validator\UniqueEmail: ~
```

---

## Summary

This reference guide provides detailed explanations for implementing DDD architecture correctly. Always remember:

1. **Domain is sacred** - No external dependencies
2. **Handlers orchestrate** - Business logic in domain
3. **Use Value Objects** - Self-validating, type-safe
4. **Respect Deptrac** - Fix code, never config
5. **Rich models** - Behavior, not just data
