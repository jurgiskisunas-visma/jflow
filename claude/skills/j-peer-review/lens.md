# The owner's review lens

Built from the owner's own inline comments on colleagues' PRs (core#9478, core#9513, core#9514, Recon#4767, Recon#4777, tna#2622, core#9595). These are the places where the bots said "approved" and a real problem was still there. Check each one against the diff; report only what you can show on the lines.

Change this file only from `correction` events recorded at the review gate, and only when the same kind of correction shows in three or more reviews.

## Flags

1. **Whose flag is read.** A flag read from the caller's token decides for the caller's company. When the protected data belongs to another company or a shared resource, the check reads the wrong company's flag.
2. **The flag check itself can throw.** A flag read placed first in a condition runs on every call, flag on or off. Find callers with no feature information in context: jobs, message handlers, anonymous endpoints.
3. **Flag-off is the old code, byte for byte.** Look for a catch, a guard, a null check or a refactor that sits outside the flag and changes the flag-off path.
4. **Flag order.** With this flag on and a related, still-off flag from another PR: is there a state the user can now reach that nothing handles yet?
5. **Turning it on in PROD.** Existing data that violates the new rule: what happens to it on the first day? When a precondition exists, ask for the check query in the PR.

## Behaviour for existing callers

6. **Before and after for each caller.** A no-op success that becomes a failure, a 200 that becomes a 404, a null that becomes an exception. Then follow one level up: a loop that stops at the first failure, a sweep that throws before finishing, a cleanup that can no longer delete legacy or tampered rows.
7. **Old paths newly reachable.** A control made visible, a status made selectable, an endpoint opened: every existing handler behind it now runs for the new case. Read those handlers.
8. **Ids that are not tied together.** A check validates object A, the action then uses id B from the same request. Is B proven to belong to A, and A to the caller's company?
9. **User-controlled text in names, paths and keys.** A file name, an attachment name or a label that flows into a storage path or a validator.

## Errors

10. **What the user gets outside Development.** A throw that becomes a generic 500 in TEST, STAGE and PROD, while the frontend matches on a message text that never arrives.
11. **Catch blocks that swallow too much.** A catch of a base exception type that also takes argument-null, timeout or bus failures and reports them as "not found" or "invalid". What does the user see during an outage?
12. **Same input, different answer.** Two endpoints that take the same bad input and answer 400 in one and 500 in the other.

## Tests

13. **Would the test fail if the code were wrong?** `It.IsAny` on the id that matters, `Times.AtLeastOnce` already satisfied by an earlier call, an assert on `IsFailure` only, so any earlier guard also passes it. Name the one-line mutation that the test would not catch.
14. **Tests outside the CI filter.** An integration or end-to-end project that calls the changed endpoint with data the new rule rejects, and is not in the solution filter CI builds.
15. **Rendered, not only computed.** A frontend spec that checks a signal or a method and never the DOM, for a change whose point is what the user sees.

## UI

16. **The other states.** Loading, empty, failed, zero rows, narrow viewport or 150% zoom. An `@else` that belongs to a different `@if` than it looks.
17. **Older issue on touched lines.** A defect that was already on the base branch, on lines the PR changes or right next to them, that the user will still see after this PR. Report it as `Older issue:`; it is the author's call.
18. **A visible change that the description does not mention.** Padding, position, wording, an option that appears. Ask whether it is intended.
