---
name: ato-company-id-lookup
description: Use when resolving an ATO company across services or databases — a OneCompanyId / company GUID from a Jira problem case, ticket or telemetry needs mapping to a shard, or a query joins the Tennants registry table in Core, Recon, Taxation or TNA. Triggers on "which shard is this company on", "resolve this company id", "OneCompanyId", "Tennants table", "find the company's database".
---

# ATO company id resolution

**OneCompanyId** is the single company GUID shared across Core, Recon, Taxation and TNA. One id resolves the company in every service that has it.

## The mapping (verified empirically on localhost,1433, 2026-06-19)

| Column | What it is |
|---|---|
| Root `Tennants.TennantId` | **= the OneCompanyId.** Same GUID across all four services for a given company |
| Root `Tennants.Id` | A **per-service surrogate** key for the registry row. Differs per service — never join on it |
| Shard `<table>.CompanyId` | **= `Tennants.TennantId`.** (Join to TennantId: match. Join to Id: no match) |

## Resolve a shard

```sql
SELECT s.DatabaseName
FROM Tennants t
JOIN Shards s ON t.ShardId = s.Id
WHERE t.TennantId = '<oneCompanyId>';
```

Run it against the **root** database of the service in question; then query the returned shard database for business rows keyed by `CompanyId = '<oneCompanyId>'`.

## The trap

`WHERE Id = '<companyId>'` returns nothing and reads like "company not found" rather than like a bug. The shipped `ato-problem-case-investigator` agent contains this wrong column (~line 126 of its agent definition) — if an investigation using that agent reports a company as absent, re-check with `TennantId` before believing it. `local-database-helper` has the correct join.

## Notes

- Local queries only from an agent; a user-level hook blocks `sqlcmd` against non-local servers.
- Confluence has more background under "OneCompanyId".

## Self-improvement

If a company lookup dead-ends again for a reason not covered here, add the case to this file (per `friction-to-skill`) rather than re-deriving it next time.
