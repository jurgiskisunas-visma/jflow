---
name: write-for-review-ato
description: The ATO-specific half of write-for-review - what the ATO reviewers check beyond the generic rules (tenancy and shards, Rebus sagas, SignalR, flag tiers, generated and shared files, test bases). ATO repos only (core, Recon, taxation, tna). Use together with write-for-review, before and while implementing in an ATO repo, and once more as a self-check on the finished diff.
---

# Write it so the ATO reviewers approve

ATO repos only. Read `write-for-review` first; these rules come on top of it. Rules marked **NEVER** are what block a PR.

### Tenancy & data access

1. Company data only through the sharded company context (`[Dependency("Company")]` / `ShardedDatabaseConnectionProvider`); cross-AO data (AO registry, flags, deletion logs) only through the root context (`[Dependency("Root")]` / `RootDatabaseConnectionProvider`).
2. **NEVER** join across shards or read company data out of the root DB.
3. Read-only queries go to `ShardedSecondaryDatabaseConnectionProvider`; heavy read traffic on the writeable shard is a finding.
4. Shard-sweeping jobs: one shard per iteration, pagination/batching, progress, cancellation, connect per shard — never one connection across the sweep.
5. Cross-context data via `IContextDispatcher.Dispatch(accountingOfficeId, query)` — never by newing up another context.
6. Command/query objects through their static factories: `ForCurrentContext()`, `ForId()`, `ForIdentity(provider, identity)`.
7. New handlers registered in the service's `UnityContainerConfigurator` (`RegistrationTrackingExtension` fails fast otherwise).
8. Redis: assume cross-tenant key collisions are possible, set a TTL on anything sensitive, keep a path that works when Redis is unreachable.

### Messaging, sagas, real-time

9. Every `Saga<T>`, `ResourceLockSagaBase<...>` and `IHandleMessages<T>` is idempotent — Rebus retries; a redelivery must not double-create, double-charge or double-publish.
10. Contention uses the resource-lock saga pattern; no ad-hoc locking.
11. **NEVER** block inside a message handler — it starves the Rebus worker pool.
12. Rebus message bodies carry an id plus minimal context — not HTML, full DTOs or big lists; the consumer fetches the rest.
13. Watch saga message frequency — every handled message is a saga-state load+save round trip.
14. Background-task → frontend progress goes over SignalR, targeted at the specific user / company / AO group, never broadcast; throttle high-frequency pushes; notification plus client fetch instead of a large payload.
15. Mutating period or financial-year state Core owns → publish the matching `PeriodContextAttributeNames` event; siblings gate on `Recon.Status` / `Taxation.Status`.
16. Synchronous Integration calls (`api/v1/...`, e.g. `Recon.ServiceClients.CoreClient`) hit a live system with no maintenance-aware filter — your call can race an in-flight Core saga.

### Feature flags

17. Tier: per-company flags (`CoreFeature`, `ReconFeatureFlag`, `TaxationFeatureFlag`, TNA `FeatureFlag`) via `this.CurrentContext.IsFeatureAvailable(...)` need an `ICurrentContext`; anywhere without one — background jobs, message handlers, Taxation `Diar`/`VismaSign` called from on-prem Bokslut — use `ConfigurationFeature` through `IConfigurationFeatureService.IsEnabled(...)`.
18. `IsFeatureAvailable` is the only legal per-company check — never re-read flags off the auth context, cache them in component state, or mirror them into environment config.
19. Flag name `<DescriptiveName>ATO<ticket>`, enum entry with an XML doc comment; next number in Core/TNA, your reserved bucket in Recon/Taxation (ranges are commented in `ReconFeatureFlag.cs` / `TaxationFeatureFlag.cs`).
20. Add the matching frontend TS enum entry by hand — it is not generated (Recon additionally mirrors into `TypeLiteNet5.ts`).
21. Frontend flag accessors are functions: `featureService.someFlag()`, never `.someFlag`.
22. Do not "clean up" the duplication between a flag's two branches — wrapper code is not duplication; collapsing the legacy branch is a blocking finding.
23. Consider mid-rollout states: half the pods on and half off, a flip while a request is in flight, a flip before the migration/cache/downstream service is ready.

### Generated & shared code, frontends

24. **NEVER** edit `vendor/ato-generated-files/` in Taxation/Recon/TNA — Core is the source of truth.
25. Changes in `vendor/ato-shared/` (Core) ripple to all four services — acknowledge the fan-out in the PR.
26. Regenerate `TypeLiteNet5.ts` and every TS mirror in the same commit as its backend source; never hand-edit them.
27. **NEVER** import one Core-repo frontend's routing/UI stack into another: Core.WebApp is `@uirouter/core` + Angular Material + ngx-bootstrap; AdminTool is `@angular/router` + `@vismaux/ngx-vud` + `ngx-permissions`; ToolSite is `@angular/router` + ngx-bootstrap.

### Context, conventions, PII

28. Context-free classes (worker jobs, VON listeners, timer/blob/service-bus triggers) carry `[NoCurrentContext("reason")]` and read nothing off `ICurrentContext` — no `CompanyId`, `AccountingOfficeId` or `IsFeatureAvailable`.
29. A new PII-bearing exportable entity gets `[ClassAnonymize(typeof(...))]` with an `IClassAnonymizer<T>`.
30. Log through static Serilog; no other logging channel.
31. Respect per-repo divergence — file-scoped namespaces everywhere except Recon (block-scoped by its `.editorconfig`); never "align" one repo to another.
32. `.resx`: Core/Taxation add new strings only to the base file with a leading `+` and never touch the Crowdin-managed locale variants; Recon mirrors the new key into all culture files. Check which repo first. Swedish strings stay Swedish. A non-empty value where the fallback path expects empty breaks `AppResourcesController.GetResources`-style tests.
33. A config key missing from `appsettings.json` is fine — App Configuration and Key Vault supply it at runtime.
34. Changes to VON event polling (`VonFor{Apy,Vpy,Con,Etax}EventManager`) — interval, batch size, per-event work — multiply load on Visma Online; match the documented contract.

### Tests (ATO idioms)

35. Backend test names `<ClassName>_<MethodName>_When<Action>_Then<ExpectedResult>` (Core/TNA/Recon also allow the `<MethodName>_When…_Then…` short form).
36. Use the repo's test base: Core `this.Resolve<T>()` / `this.CreateEntity<T>()`; Recon `AutoMockTestBase<TSut>` with `Sut` and `EnableFeature()`/`DisableFeature()`; TNA `this.Target` / `this.GetMock<T>()`.
37. Mock `ICurrentContext.IsFeatureAvailable(...)` with the Moq accessor the member actually needs — `SetupGet` for a property, `Setup` for a method; the wrong one silently returns default and the test passes for the wrong reason.
38. A flag-gated test actually enables the flag in the mock, or the new path is never exercised despite a green test.
39. Frontend: `Mockery` enables all flags by default — disable explicitly only when testing the legacy branch; a signal-based flag stub is a callable that returns the value, not a truthy object.
40. Never double-mock two layers of the same feature check; mock setup is exactly what the test needs.
