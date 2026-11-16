---
name: write-for-review
description: The checklist code reviewers (sceptic, code, architect, performance, security, test-coverage, feature-flag) apply to a diff, turned into rules for the person WRITING the code — so the diff passes review first time and no per-implementation review round is needed. Generic .NET / Angular / TypeScript rules; a project adds its own half as write-for-review-<project>. Rules marked NEVER are what block a PR. Use before and while implementing, and once more as a self-check on the finished diff.
---

# Write it so the reviewers approve

Read this before you write a line, and once more against the finished diff. Rules marked **NEVER** are what block a PR. This list is derived from the reviewer agents' own prompts; it is what they will look for, written down in advance so they find nothing.

Clean Code basics (naming, small functions, no comments, SOLID) are in the `clean-code` skill and not repeated here.

## Generic rules (.NET / Angular / TypeScript)

### Correctness & failure modes

1. **NEVER** mix sync and async: no `.Result`, `.Wait()`, `.GetAwaiter().GetResult()` on an async path — propagate `async` top to bottom.
2. Suffix every method returning `Task`/`Task<T>` with `Async`.
3. Every error path propagates — no catch that swallows; rethrow, return a typed failure, or log with the exception object.
4. Return a *successful* result carrying a `Conflict`/`NotFound` outcome for user-actionable conditions; reserve `Result.Failure` for genuine faults (a Failure becomes a 500, not a 4xx).
5. Normalize every `DateTime` to UTC before it crosses the wire — `DateTimeKind.Unspecified` renders as the wrong date in the browser.
6. Match `null` / `""` / `[]` semantics across layers: if the backend trims and rejects whitespace, the frontend validates the trimmed value too; empty collection equals null wherever the spec says "not available".
7. Recheck every date boundary against the spec wording — inclusive vs exclusive, `AddDays(-3)`, same-day vs overnight.
8. When you change one branch of a sibling pair (overload, sibling handler, sibling template control, sibling filter set), change the other or state why they legitimately differ.
9. Handle empty/null/whitespace, single-element and very-large-collection inputs explicitly in any new parser or import path.
10. Dispose everything disposable (`using`); cancel-check any method that accepts a `CancellationToken`.
11. Assume a retry can arrive while the original call is in flight — new writes must be safe to run twice.
12. Give new SQL migrations a reversal path; never an unbatched long `ALTER TABLE`/`UPDATE` on a high-traffic table.

### Code quality

13. **NEVER** use `any` in new TypeScript — `unknown` plus a type guard; `as` casts need a one-line justification; `@ts-ignore`/`@ts-expect-error` need a JIRA reference.
14. **NEVER** nest `.subscribe()` — `switchMap` (cancellable HTTP), `mergeMap` (parallel), `concatMap` (ordered), `exhaustMap` (ignore while in flight).
15. **NEVER** leave a subscription without declarative cleanup — `takeUntilDestroyed()`, `DestroyRef`, or the async pipe.
16. `toSignal()` instead of a `.subscribe()` that only writes into a signal; mutate signals with `set()`/`update()`, never in place.
17. **NEVER** put a ternary chain in a template — extract a named `computed()`. Pipe chains longer than two also come out.
18. Methods under 30 lines (over 50 blocks), nesting depth ≤3 (over 4 blocks), parameters ≤4.
19. Before adding a service / endpoint / DTO / helper / constant, grep for an existing provider of that concept and reuse it. A tiny change that needs new cross-layer machinery is the signal you missed an existing abstraction.
20. Do not add a backend round-trip for something the client already knows.
21. Extract a helper at three-plus near-identical blocks; a one-off block stays inline.
22. No speculative extensibility, unused abstraction layers, or config options nobody asked for.
23. Delete dead code, commented-out code, unused imports/params/private helpers, and every `console.log` / `Debug.WriteLine` before pushing.
24. Update the XML doc, inline comment, README and PR description that describe the behaviour you changed — doc-vs-code drift inside the diff is the cheapest finding a reviewer makes.
25. PR title, description and diff agree on scope; anything beyond the stated fix is named in the body.
26. Match the neighbouring files' error-handling shape, DI registration style and file layout — never a second way to solve the same problem.
27. `Log.Information` for expected branches, `Log.Error` only for genuine failures; no log line duplicating one upstream.
28. Angular: standalone components (no `standalone: true`), `input()`/`output()` functions, `inject()` over constructor injection, `ChangeDetectionStrategy.OnPush`, native `@if`/`@for`/`@switch`, no `@HostBinding`/`@HostListener`.
29. Stateful UI controls are real `<button>`s with `aria-expanded`; nav items have `href`; every form control is labelled.

### Architecture & layering

30. Flow is Controller → command/query → handler → Logic → Data; **NEVER** business logic or direct data access in a controller.
31. Commands mutate and return only success/failure/id; queries are side-effect-free.
32. **NEVER** register a component with a longer lifetime than a dependency it captures — a singleton holding a scoped/per-request/per-message dependency freezes it at first resolve.
33. Register every new handler/service in the DI container in the same commit — the container fails fast on resolve.
34. **NEVER** add an endpoint without its authorization attributes, under the scope matching its caller (frontend vs service-to-service vs admin).
35. **NEVER** change a published contract's shape without a backward-compatible design *and* a version bump plus a coordinated consumer update.
36. Long-running or heavy work (imports/exports, document generation, bulk jobs) goes behind a message on the bus into the worker process, not on the request path.

### Performance

37. **NEVER** issue a query or HTTP call per item in a loop — batch it.
38. **NEVER** return an unbounded result set from a user-facing endpoint; paginate or `Take()`.
39. `AsNoTracking()` on read-only EF queries; `.Select()` the columns you need; `.AsSplitQuery()` when two or more collection `Include`s are present.
40. Keep evaluation server-side — do not cross `IQueryable`→`IEnumerable` before filtering.
41. Hoist DI resolutions, feature-flag checks and context lookups out of per-row loops.
42. Independent awaits run with `Task.WhenAll`, not sequentially.
43. No mid-chain `.ToList()`, no string concatenation in loops (`StringBuilder`), no `List.Contains()` in a loop (`HashSet`); `TryGetValue` over `ContainsKey` + indexer.
44. Add an index for any column a new query filters, joins or orders on in a large table.
45. Every `@for` has a `track`; heavy computation stays out of templates and getters (`computed()`); no freshly-constructed objects/arrays as component inputs.
46. Import subsets, not whole libraries, into shipped bundles.

### Security

47. **NEVER** build SQL by string concatenation — parameterize, including raw ADO.NET escape hatches.
48. **NEVER** filter tenant-scoped data by a key taken from user input; take it from the authenticated session.
49. **NEVER** pass a request-supplied host or URL to `HttpClient` without a hostname allowlist — it leaks managed-identity tokens from the instance metadata endpoint.
50. **NEVER** commit a secret, API key or connection string with embedded credentials; managed identity first, else Key Vault / environment.
51. No token in a URL; no diffs/patches in long-lived shell variables; CI tokens scoped to the repositories and permissions actually needed.
52. Structured Serilog placeholders (`Log.Information("{User}", user)`), never concatenated strings; never log PII, org numbers, transaction detail or credential-bearing objects.
53. Validate every external input at the boundary — type, length, range, format, allowlist — including uploaded file size, content type and filename before any path join.
54. Sanitize before `[innerHTML]`; **NEVER** `bypassSecurityTrust*` on user content.
55. Error responses carry no stack traces, internal paths or system detail; distinct status codes per failure mode.
56. Standard crypto only — `RandomNumberGenerator` not `Random`, RSA ≥2048 / AES-256, bcrypt/argon2/scrypt for passwords.
57. Write code behind a disabled flag as if it were live — a flag is not a security control.

### Tests

58. **NEVER** merge a new public method, handler, component, service, pipe or directive without a test; modifying untested code means at minimum testing the new behaviour.
59. Three paths per changed behaviour: happy path, the error path you introduced, and each boundary you crossed (DB, cache, real-time channel, HTTP, storage, frontend↔backend endpoint pair).
60. Assert behaviour, not invocation — the saved entity's fields and the emitted payload, not `Verify(x => x.Save(It.IsAny<T>()))`; the test name matches what the code actually returns; frozen mock expectations are updated after a refactor.

### Feature flags & PR hygiene

61. **NEVER** ship a behaviour change ungated: new endpoint, new/changed business logic, new UI entry point that calls the server, changed user-visible algorithm, new real-time message type, new external integration.
62. Legacy behaviour stays in the `else` branch until rollout; only a purely additive change (new file, new endpoint replacing nothing) may omit it.
63. Frontend and backend ends of one change gate under the same flag name, present in both enums, polarity checked — new behaviour in the flag-*on* branch.
64. A change that genuinely cannot be flagged (infra, DI/startup, migration, atomic cross-service shape change) gets, in the PR body: why, which changes ship as one bundle, and an explicit "no flag — verify in QA before prod" note.
65. Diff scoped to production code changes and their tests — no drive-by refactors of code the ticket does not touch.

## Project-specific rules

A project may add its own half as a skill named `write-for-review-<project>` (ATO: `write-for-review-ato`). When the task's project has one, read it too; never apply another project's.
