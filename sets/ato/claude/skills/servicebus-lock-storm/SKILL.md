---
name: servicebus-lock-storm
description: Use when ATO production telemetry shows MessageLockLost, "Error when renewing peek lock for message with ID", ObjectDisposedException from CancellationTokenSource in a Rebus receive path, an exception flood on a ~10s cadence, or messages silently dead-lettered with MaxDeliveryCountExceeded despite a high Rebus maxDeliveryAttempts. Triggers on "lock lost storm", "peek lock errors", "messages dead-lettered silently", "Rebus.AzureServiceBus".
---

# Service Bus lock-loss storm — known root cause

**Do not re-investigate this from scratch.** It is a library bug in `Rebus.AzureServiceBus` 10.5.x–10.7.0, not ATO code. Filed upstream as [issue 117](https://github.com/rebus-org/Rebus.AzureServiceBus/issues/117), tracked internally as ATO-19735, **fixed in 10.7.1** (2026-08-17).

## Signature

- `"Error when renewing peek lock for message with ID {messageId}"` repeating every ~10s, for hours, with **no handler running** (the 4:30 `TimeoutMessageHandler` watchdog never logs).
- `ObjectDisposedException: The CancellationTokenSource has been disposed` out of `AzureServiceBusTransport.Receive` — logged from Rebus core `ThreadPoolWorker.cs:159`, so the exception arrives as a *format argument*, not via the `Warn(Exception, …)` overload. Log-capture must match on text.
- Redeliveries spaced exactly `LockDuration` apart, ending at `MaxDeliveryCount` × `LockDuration`, then a **silent native dead-letter** (`reason=MaxDeliveryCountExceeded`) that bypasses Rebus retry entirely.

## Mechanism

A per-message linked `CancellationTokenSource` is stored in `_messageRenewerTokenSources` keyed by `MessageId`, cleaned up only in OnAck/OnNack/OnDisposed. A missed cleanup leaks for the process lifetime: the 10s renewal sweep keeps renewing a message nobody handles, and on redelivery of that same MessageId `TryAdd` fails, the code disposes the token source and then still reads its `.Token` → throws from `Receive`.

## Scope

`AutomaticallyRenewPeekLock()` is enabled on **9 endpoints across all 4 services** (core CoreEndpoint / FeatureActivation / Maintenance, docconv PdfGeneration, tna Jobs, Recon Recon + Maintenance, taxation Taxation + Maintenance) — not docconv-only.

**Dropping `AutomaticallyRenewPeekLock()` was never a valid mitigation** — the token source is created outside that guard, and disabling renewal makes lock lapses more likely.

## State / what remains

- 10.7.1 verified by same-environment A/B against the repro suite (`D:\Projects\rebus-asb-failure-proof`, public mirror `jurgiskisunas-visma/rebus-asb-failure-proof`): 10.7.0 fails all 3, 10.7.1 passes all 3.
- Remaining rollout: bump 10.5.1 → 10.7.1 in `common.common`, publish `Messaging.Configuration`, roll to Core / Recon / Taxation / TNA. Two-minor jump — do a messaging regression pass.
- The permanent-renewer-leak half (983 errors / 167 min) never reproduced locally; it likely needs the renewal-failure path (`Cancel()` without dictionary removal). Confirmable only by watching PROD after the upgrade.
- Monitoring gap by team decision: the only DLQ alert is `DeadletteredMessages > 10000`, so single silent dead-letters stay invisible, and the ~90 existing dead-lettered messages will not be reprocessed.

## If the signature does not match

Then it is a different problem — check for a transient Service Bus fault during an import wave (duplicates arriving via header-borne lease-key re-entry) before assuming this bug.

## Self-improvement

When the PROD-after-upgrade observation lands, update the "State" section here — this file is the runbook that keeps the next storm from becoming another multi-day investigation.
