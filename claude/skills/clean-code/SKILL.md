---
name: clean-code
description: Robert C. Martin's Clean Code rules, condensed into enforceable checks for writing or reviewing production code — naming, function size, argument count, comment discipline (near-zero comments; expressive names instead), error handling, class design, SOLID, test quality (F.I.R.S.T.), and the Boy Scout Rule with its scope limits. Use when writing new code, refactoring, reviewing a diff for quality, or deciding whether a comment is justified. Triggers on "clean code", "uncle bob", "SOLID", "should this have a comment", "is this function too long", "boy scout rule", "naming review".
---

# Clean Code — enforceable rules

Source: Robert C. Martin, *Clean Code* (2008) and *Clean Coder* / *Clean Architecture*. Condensed to what changes a decision while writing or reviewing code.

The governing principle: **code is read far more often than it is written.** Optimise for the reader. Every rule below is downstream of that.

The second governing principle: **these are heuristics, not laws.** A rule that makes the code harder to read in a specific case loses to readability in that case. Deviating is allowed; deviating silently is not — say why.

---

## 1. Names

- A name must answer *why it exists, what it does, and how it is used*. If it needs a comment to do that, the name failed.
- No disinformation. `accountList` that is not a List is a lie. `hp`, `aix`, `sco` mean something else to someone.
- Make meaningful distinctions. `a1`, `a2`, `ProductInfo` vs `ProductData`, `getActiveAccount` vs `getActiveAccounts` vs `getActiveAccountInfo` — noise words carry no information.
- Use pronounceable, searchable names. Single letters are acceptable only as local loop counters in a tiny scope. A constant `7` is unsearchable; `MAX_RETRY_ATTEMPTS` is not.
- No type or scope encodings: no Hungarian notation, no `m_` prefix, no `I` prefix on interfaces when the language does not require it. Follow the repo's existing convention when it disagrees — consistency within a codebase outranks this rule.
- Classes are noun phrases. Methods are verb phrases. Accessors, mutators and predicates are `get…`, `set…`, `is…`/`has…`.
- One word per concept. Pick `fetch` or `get` or `retrieve` and use it consistently for the same operation across the codebase.
- Add meaningful context through classes and namespaces, not through prefixes. `Address.state` beats `addrState`.
- Scope rule of thumb: short names for short scopes, long names for long scopes. A variable alive for three lines does not need a paragraph of a name; a public API member does.

## 2. Functions

- **Small.** Then smaller. Long functions are the single most common readability failure.
- **Do one thing.** A function does one thing when you cannot extract another function from it with a name that is not merely a restatement of its implementation.
- **One level of abstraction per function.** Do not mix high-level policy and low-level string slicing in the same body.
- Read top-down: each function is followed by those at the next level of abstraction down (the Stepdown Rule).
- **Arguments: fewer is better.** Zero is ideal, one or two are fine, three needs justification, four or more almost always means a missing parameter object or a missing type.
- No flag arguments. A boolean parameter proves the function does two things — split it, or make it an enum whose name says what it selects.
- **No side effects.** A function named `checkPassword` must not also initialise the session. Names are promises.
- Command-Query Separation: a function either *does* something or *answers* something, never both.
- Prefer exceptions to returned error codes. Error codes force the caller into nested `if` handling and force the codebase into a dependency magnet enum.
- Extract `try`/`catch` bodies into their own functions. Error handling is one thing, so a function that handles errors should do nothing else.
- **DRY** — duplication is the root of most maintenance cost. But three identical lines of trivial setup in two tests are not duplication worth an abstraction; premature deduplication couples things that only happened to look alike.

## 3. Comments — the hard rule

> "The proper use of comments is to compensate for our failure to express ourselves in code. Comments are always failures."

Target: **close to zero comments.** Before writing one, try to make the code say it: extract a function whose name is the comment, introduce an explaining variable, or rename something.

**Allowed comments — this is the whole list:**

1. **Contract / API documentation comments** that are extracted into generated docs or IDE tooltips — XML doc comments (`///`), JSDoc/TSDoc, Javadoc, docstrings — on **public API surface**: published types, public methods, exported functions, REST endpoints, message contracts. These document the contract, not the implementation.
2. **Legal / licence headers** where required.
3. **Warning of consequences** a reader would otherwise not expect ("this test takes 4 minutes", "not thread-safe").
4. **Explanation of a non-obvious *why*** — a business rule, a workaround for an external bug, a decision that looks wrong and would otherwise be "fixed" back into a defect. One short line. Include the reason, not the mechanism.
5. **`TODO` with a tracking reference** — only when it is genuinely going to be picked up and a ticket exists.

**Forbidden comments:**

- Redundant comments restating the code (`// increment i`).
- Commented-out code. Delete it — version control remembers.
- Journal / changelog comments, author attributions, "modified by X on date". Version control remembers that too.
- Section banners, closing-brace comments, noise (`// default constructor`).
- Doc comments on **private** methods, internal helpers, or test methods. The name carries the meaning. A test name that needs a comment is a badly named test.
- Any comment that will silently rot when the code beside it changes.

## 4. Formatting

- Follow the codebase's existing formatter and style. An automatic formatter's output ends the argument.
- Vertical density: related lines stay together; blank lines separate concepts.
- Vertical distance: declare variables close to their use; keep callers and callees near each other.
- Keep lines short enough to read without horizontal scrolling.
- Team style beats personal style, always.

## 5. Objects and data structures

- **Objects** hide data and expose behaviour. **Data structures** expose data and have no meaningful behaviour. Do not create hybrids that do both badly.
- **Law of Demeter**: talk to friends, not strangers. `a.getB().getC().doSomething()` is a train wreck; it couples you to the whole chain.
- Tell, don't ask: send an object a message rather than pulling its state out to decide for it.
- Data Transfer Objects are legitimately dumb. Do not add behaviour to them for symmetry.

## 6. Error handling

- Error handling is one thing. It must not obscure the main logic.
- Use exceptions, not return codes; use unchecked exceptions by default.
- Throw exceptions with context: what operation failed, on what, and why. An exception message is read at 3 AM by someone who is not you.
- **Never return `null`. Never pass `null`.** Return an empty collection, an optional/maybe type, or a null-object. Every returned `null` is a `NullReferenceException` waiting for a caller who forgot.
- Wrap third-party APIs at the boundary so their exception taxonomy does not leak through the whole codebase.
- Never swallow an exception silently. An empty `catch` block is a defect.
- Do not log-and-rethrow the same exception at every layer; handle it once, where the decision can actually be made.

## 7. Boundaries

- Keep third-party code at the edges. Wrap it; depend on your own interface, not theirs.
- Learning tests: when adopting an unfamiliar library, write small tests that prove how it actually behaves, not how the docs say it does.
- Code at a boundary needs clear separation and tests that define expectations, so a version upgrade breaks a test rather than production.

## 8. Tests

**F.I.R.S.T.**

- **F**ast — slow tests do not get run.
- **I**ndependent — no ordering between tests, no shared mutable state.
- **R**epeatable — same result on any machine, any time, offline. No dependency on wall-clock time, locale, network, or leftover data.
- **S**elf-validating — boolean pass/fail. No reading the console to decide.
- **T**imely — written just before the production code that makes them pass.

Further rules:

- **Test code is production code.** It gets the same naming, structure and cleanliness standards. Dirty tests are worse than no tests because they rot into a maintenance liability and eventually get deleted.
- **One assert concept per test.** Multiple physical asserts are fine when they check one logical outcome; testing three unrelated behaviours in one test is not.
- The test name is the specification. It states the scenario and the expected outcome. It needs no doc comment.
- Build-Operate-Check (Arrange-Act-Assert) structure, visible at a glance.
- Test the **failure paths**, not only the happy path. Untested error handling is untested by definition.
- A test must be able to fail. If you cannot describe the change that would break it, it asserts nothing.
- Never weaken a test to make it pass. Never delete a failing test to go green. Fix the code, or fix the test's premise deliberately and say so.
- Do not mock what you do not own and do not mock the thing under test. An over-mocked test verifies the mock, not the behaviour.

## 9. Classes

- **Small.** Measured in responsibilities, not lines.
- **Single Responsibility Principle**: one reason to change. A class whose description needs the word "and" is doing two things.
- High cohesion: methods use the instance variables; when a subset of methods uses a subset of fields, a class is trying to split — let it.
- Organise for change: structure so that a likely future change touches one place.
- Depend on abstractions, not concretions, at the points where change is expected — **not everywhere**. An interface with exactly one implementation and no plausible second one is speculative coupling, not decoupling.

## 10. SOLID

- **S**ingle Responsibility — one reason to change.
- **O**pen/Closed — open to extension, closed to modification.
- **L**iskov Substitution — a subtype must be usable anywhere its base type is, without surprising the caller.
- **I**nterface Segregation — many small client-specific interfaces beat one fat one; no client should depend on methods it does not use.
- **D**ependency Inversion — high-level policy must not depend on low-level detail; both depend on abstractions.

## 11. Code smells to hunt

Rigidity (small change forces changes everywhere) · Fragility (a change breaks something unrelated) · Immobility (nothing can be reused elsewhere) · Needless complexity · Needless repetition · Opacity · Dead code · Speculative generality (built for a requirement that does not exist) · Feature envy (a method more interested in another class's data than its own) · Long parameter lists · Primitive obsession · Shotgun surgery · Inconsistent conventions · Magic numbers · Misplaced responsibility · Vertical separation of a variable from its use.

## 12. The Boy Scout Rule

> "Leave the campground cleaner than you found it."

Improve what you touch, on every commit. In practice:

**Do, without asking:**
- Rename a badly named variable, parameter or private method inside the code you are already changing.
- Delete a redundant or rotted comment you read while working.
- Extract an obviously over-long function you are already editing into named pieces.
- Delete dead code you can prove is unreachable.
- Remove a stray `Console.WriteLine` / `console.log` / debug print.
- Fix formatting the repo's own formatter would fix.

**Do not, without asking:**
- Rename anything public, exported, serialised, persisted, or crossing a service boundary.
- Restructure a file you are not otherwise changing.
- Change behaviour in the name of cleanliness. A refactor is behaviour-preserving by definition; if behaviour changes, it is a feature or a bug fix, and it belongs in its own change with its own reasoning.
- Mix a large refactor into a feature or fix commit — it hides the real diff from the reviewer and makes the change impossible to revert cleanly.
- Touch anything outside the ticket's scope because it offends you. Note it, and move on.

**The size test:** if the cleanup makes the reviewer's job easier, it belongs in the change. If it makes the reviewer hunt for the actual fix, it belongs in a separate one.

## 13. The senior bar — elegance without over-engineering

Clean Code is not an invitation to build a framework. The failure mode of applying these rules enthusiastically is code that is technically compliant and practically unreadable: nine one-line classes, three interfaces with one implementation each, and a factory to wire them.

Test any abstraction against these:

- **YAGNI.** Build for the requirement in front of you. Speculative generality is a smell in Martin's own list.
- **Does it earn its keep?** An abstraction must remove more complexity than it adds. Count the indirections a reader must follow to answer "what does this actually do".
- **Rule of three.** Deduplicate at the third occurrence, not the first. Two similar things may be coincidence.
- **Would a senior reviewer ask "why is this here?"** If yes, it is either wrong or it needs the one-line *why* comment that rule 3.4 permits.
- **Robust, not paranoid.** Handle the errors that can actually occur at this boundary. Do not defensively guard against states the type system or the caller already prevents — dead defensive code is untested, untestable, and it lies to the reader about what can happen.
- **Cover main cases and real edge cases; stop at the absurd.** A retry-with-jitter around a flaky network call is engineering. A retry around an in-process function call is noise.
- **The simplest thing that is fully correct wins.** Elegance is having nothing left to remove, not having every pattern applied.
