workspace "Service architecture" "C4 model of the service: system context, containers and components." {
    !identifiers hierarchical
    model {
        properties {
            "structurizr.groupSeparator" "/"
        }
        apiClient = person "API client" "A person or program that calls the REST and GraphQL API."
        system = softwareSystem "Service" "A billing service built from the Rust template." {
            database = container "Database" "Stores the data of every bounded context." "PostgreSQL 16" {
                tags "Database"
            }
            service = container "Service binary" "Serves REST under /api, GraphQL at /api/graphql, /api/health and /ping; also runs migrations and exports the API contracts." "Rust, axum, tokio" {
                compositionRoot = component "service" "Composition root: CLI, configuration, wiring, router, middleware, OpenAPI document, GraphQL schema." "Rust crate"
                group "Shared" {
                    group "Shared/Domain" {
                        sharedDomain = component "shared-domain" "Aggregate root, domain event, bus ports, technical ports, UUID and page value objects." "Rust crate" {
                            tags "Domain"
                        }
                    }
                    group "Shared/Application" {
                        sharedApplication = component "shared-application" "Problem document, problem-aware extractors, fallbacks, GraphQL error helpers." "Rust crate" {
                            tags "Application"
                        }
                    }
                    group "Shared/Infrastructure" {
                        sharedInfrastructure = component "shared-infrastructure" "In-process buses, clock, UUID generator, connection pool and migrator." "Rust crate" {
                            tags "Infrastructure"
                        }
                    }
                }
                group "Internal/HealthCheck" {
                    group "Internal/HealthCheck/Domain" {
                        healthCheckDomain = component "health-check-domain" "HealthProbe port, Dependency and HealthReport value objects." "Rust crate" {
                            tags "Domain"
                        }
                    }
                    group "Internal/HealthCheck/Application" {
                        healthCheckApplication = component "health-check-application" "HealthService and the GET /api/health handler." "Rust crate" {
                            tags "Application"
                        }
                    }
                    group "Internal/HealthCheck/Infrastructure" {
                        healthCheckInfrastructure = component "health-check-infrastructure" "PostgreSQL probe." "Rust crate" {
                            tags "Infrastructure"
                        }
                    }
                }
                group "Billing/Invoice" {
                    group "Billing/Invoice/Domain" {
                        invoiceDomain = component "invoice-domain" "Invoice aggregate, value objects, issued event, repository port." "Rust crate" {
                            tags "Domain"
                        }
                    }
                    group "Billing/Invoice/Application" {
                        invoiceApplication = component "invoice-application" "Issue command, get and list queries, audit subscriber, REST handlers, GraphQL resolvers." "Rust crate" {
                            tags "Application"
                        }
                    }
                    group "Billing/Invoice/Infrastructure" {
                        invoiceInfrastructure = component "invoice-infrastructure" "PostgreSQL repository adapter." "Rust crate" {
                            tags "Infrastructure"
                        }
                    }
                }
                compositionRoot -> sharedApplication "Uses fallbacks and middleware"
                compositionRoot -> sharedInfrastructure "Builds the buses and the connection pool"
                compositionRoot -> healthCheckApplication "Mounts the health route"
                compositionRoot -> healthCheckInfrastructure "Registers the probes"
                compositionRoot -> invoiceApplication "Mounts routes, registers handlers and subscribers"
                compositionRoot -> invoiceInfrastructure "Registers the repository"
                compositionRoot -> sharedDomain "Wires the bus, clock and UUID ports"
                compositionRoot -> healthCheckDomain "Collects the probes behind the HealthProbe port"
                compositionRoot -> invoiceDomain "Holds the repository behind the repository port"
                sharedApplication -> sharedDomain "Uses bus errors"
                sharedInfrastructure -> sharedDomain "Implements bus, clock and UUID ports"
                healthCheckDomain -> sharedDomain "Uses the shared error type"
                healthCheckApplication -> healthCheckDomain "Runs probes through the HealthProbe port"
                healthCheckApplication -> sharedApplication "Returns problem documents"
                healthCheckApplication -> sharedDomain "Formats the error chain of a failed probe"
                healthCheckInfrastructure -> healthCheckDomain "Implements HealthProbe"
                healthCheckInfrastructure -> sharedDomain "Uses the shared error type"
                invoiceDomain -> sharedDomain "Uses aggregate root, events and value objects"
                invoiceApplication -> invoiceDomain "Uses the aggregate and the repository port"
                invoiceApplication -> sharedDomain "Dispatches through the bus ports"
                invoiceApplication -> sharedApplication "Uses extractors and problem documents"
                invoiceInfrastructure -> invoiceDomain "Implements the repository port"
                invoiceInfrastructure -> sharedDomain "Uses shared value objects"
                sharedInfrastructure -> database "Opens the connection pool and applies migrations" "SQL over TCP"
                healthCheckInfrastructure -> database "Runs SELECT 1" "SQL over TCP"
                invoiceInfrastructure -> database "Reads and writes invoices" "SQL over TCP"
            }
        }
        apiClient -> system.service "Calls the REST and GraphQL API" "HTTP, JSON"
    }
    views {
        systemContext system "SystemContext" "The service, its callers and the systems it depends on." {
            include *
            autolayout lr
        }
        container system "Containers" "The service binary and its database." {
            include *
            autolayout lr
        }
        component system.service "Components" "One component per workspace crate, grouped by bounded context and layer." {
            include *
            autolayout tb
        }
        styles {
            element "Person" {
                shape Person
            }
            element "Database" {
                shape Cylinder
            }
            element "Domain" {
                background #2e7d32
                color #ffffff
            }
            element "Application" {
                background #1565c0
                color #ffffff
            }
            element "Infrastructure" {
                background #6a1b9a
                color #ffffff
            }
        }
    }
}
