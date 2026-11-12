# Extension seams

The template ships what its requirements ask for and nothing more. Features that a service often needs are left out on purpose, and each has one named place where it plugs in. This document says where that place is, what to add and what to leave alone. The examples name the crates and files of the template; adapt them to the names of your service.

Most seams change files that the template sync keeps in step with the template. Read [Seams and the template sync](#seams-and-the-template-sync) before you change one: each seam lists the synchronised files it changes, and each of them goes into your `.templatesyncignore` in the same pull request.

## Contents

- [Redis adapter through the `Cache` port](#redis-adapter-through-the-cache-port)
- [Outbox for domain events](#outbox-for-domain-events)
- [Seams and the template sync](#seams-and-the-template-sync)

## Redis adapter through the `Cache` port

The port is `shared_domain::port::Cache`:

```rust
#[async_trait::async_trait]
pub trait Cache: std::fmt::Debug + Send + Sync {
    async fn get(&self, key: &str) -> Result<Option<Vec<u8>>, CacheError>;
    async fn set(&self, key: &str, value: Vec<u8>, ttl: std::time::Duration) -> Result<(), CacheError>;
}
```

The shipped adapter is the in-process `shared_infrastructure::cache::MokaCache`. A remote cache is an adapter for the same port:

1. Add the Redis client crate to `crates/shared/infrastructure/Cargo.toml` and to the allow-list of that layer in `architecture.toml`. The change to `architecture.toml` is protected configuration and needs the label `approved-config-change`.
2. Add `shared_infrastructure::cache::RedisCache` next to `MokaCache`, implement `Cache` for it, and give it a `Debug` implementation that never prints keys or values.
3. Add the settings (URL, timeouts) to the configuration of the `service` crate. Every setting is an environment variable: add each to `.env` and to `.env.test` where tests need it.
4. Construct the adapter in `Adapters::connect` and hand it to `CacheProbe` instead of `MokaCache`. The handler of `/api/health` and `HealthService` do not change.

## Outbox for domain events

Domain-event delivery is at most once. A service whose subscribers must not miss an event needs a transactional outbox:

1. Add a migration pair that creates an `outbox` table in the context that owns the events (`make create-migration name=create_outbox`).
2. Introduce a unit-of-work port in the Domain crate of the context, with an adapter in its Infrastructure crate that saves the aggregate and inserts the outbox rows in one SQL transaction.
3. Add a relay that reads unpublished rows in order, publishes them and marks them as published. Delivery then becomes at least once, so every subscriber must be idempotent.
4. Regenerate `.sqlx/` with `make sqlx-prepare` and commit it with the new files under `migrations/`.

## Seams and the template sync

The template sync (see the sync guide, `TEMPLATE_SYNC_APP.md` or `TEMPLATE_SYNC_PAT.md` in the `.github` directory) resolves every difference in favour of the template, so a sync pull request removes what a service added to a synchronised file. The template does not put the files of these seams on its own ignore list on purpose: a fix of the router, the request span or the shutdown sequence must keep reaching every service that has not changed them. A service that uses a seam therefore:

1. Adds every synchronised path that the seam changes, as listed under the seam, to its own `.templatesyncignore` in the same pull request as the change. Check a path with `git ls-files -ci --exclude-from=.templatesyncignore -- <path>`: it prints the path once it is ignored.
2. Applies later template changes to these files by hand, as the section "Apply an ignored change by hand" of the sync guide describes.
3. Removes a path from its `.templatesyncignore` again when it drops its change to that file, so that the template's version arrives.
