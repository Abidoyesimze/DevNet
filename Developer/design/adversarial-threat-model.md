# Adversarial threat model — DIN Protocol (task_240926_17, Part 1)

**Status:** Draft — open for Umer review before Part 2 tests are written  
**Date:** 2026-09-28  
**Base:** `develop` @ post-PR-#171/#172/#173  
**Author:** @robertocarlous

This is a targeted threat model for the DIN Protocol on-chain coordination layer.
It does not cover off-chain model training, IPFS layer security, or the CLI.
Each scenario maps to one `test_defended_…`, `test_costBounded_…`, or `test_knownGap_…`
entry in `foundry/test/P3Adversarial.t.sol`.

---

## Scenario matrix

### Row 1 — Sybil N-identity no-participation

| Field | Value |
|---|---|
| **Attacker** | Sybil operator: N validator identities, each staking MIN_STAKE |
| **Capability** | Creates N accounts, deposits MIN_STAKE per account, registers each GI, never submits |
| **Protocol response today** | Concurrent-registration cap gates entry: `maxAllowed = stake / MIN_STAKE × capPerUnit` (`DINTaskCoordinator.sol:388`). Each identity that registers but submits nothing triggers `slashPartial` (S2: `AGG_T1_NO_SUBMISSION`) and then `recordNoParticipation` (S6) — `S6PartialSlashFired` at threshold (`DinValidatorStake.sol:351`). |
| **Expected test outcome** | **COST-BOUNDED** — the attack succeeds in occupying seats, but the cost is `N × MIN_STAKE` stake at risk per GI. The test asserts (a) the cap prevents registering more identities than stake allows, and (b) each no-show is slashed S2+S6 up to the S6 threshold, leaving a measurable net cost per seat captured. |
| **Trust assumption** | Concurrent-registration cap (`capPerUnit`) is set high enough that stake-per-seat cost is economically significant relative to the model reward. |

---

### Row 2 — Sybil seat capture in audit batch or T1 subgroup

| Field | Value |
|---|---|
| **Attacker** | Sybil operator: k identities, each staking MIN_STAKE, targeting k-of-n seats in one batch |
| **Capability** | k × MIN_STAKE total stake; no control of randomness (batch assignment is `_shuffleUintArray`, seeded from `block.timestamp + msg.sender`) |
| **Protocol response today** | No Sybil-specific defence beyond the per-identity stake requirement. The attacker captures k-of-n seats with probability proportional to k/n across shuffle permutations. `_shuffleUintArray` seed is grindable (see #156 for the separate issue). |
| **Expected test outcome** | **COST-BOUNDED** — the test sets up n registered identities, k of which are Sybil, and asserts (a) the fraction of batches where the Sybil controls a majority is ≈ k/n (bounded by stake spent), and (b) the total stake at risk is `k × MIN_STAKE`. If k/n ≥ majority threshold, the wrong CID wins in that batch. |
| **Trust assumption** | `n` (total registered aggregators/auditors) is large enough that `k × MIN_STAKE` to control majority is economically prohibitive relative to the poisoned-model gain. |

---

### Row 3 — Recidivist missing votes → S5 escalation and jail

| Field | Value |
|---|---|
| **Attacker** | Validator repeatedly misses S1 votes (or S2 submissions) across GIs |
| **Capability** | Registers each GI, never votes; collects a partial slash each time |
| **Protocol response today** | `slashPartial` in `DinValidatorStake.sol:294` maintains a per-validator, per-slasher rolling GI list. When slashes in the last `s5RecidivismWindow` (default: 5) GIs reach `s5RecidivismThreshold` (default: 3), the slash is automatically escalated to full `MIN_STAKE` and the validator is jailed for `s5JailDuration` (default: 7 days). `isValidatorActive` returns `false` while jailed (`DinValidatorStake.sol:541`), blocking registration in the next GI. |
| **Expected test outcome** | **DEFENDED** — the test runs the attacker through `s5RecidivismThreshold + 1` GIs of missed votes, asserts S5 escalation fires (`ValidatorEscalatedS5` event), validator is jailed, and `isValidatorActive` is `false` after the last slash. A subsequent registration attempt reverts. |
| **Trust assumption** | None beyond correct implementation of S5 counter in `DinValidatorStake` (verified by `SlashingInvariants.t.sol`). |

---

### Row 4 — Auditor bloc approves poisoned client model (S3 shadow-mode)

| Field | Value |
|---|---|
| **Attacker** | Auditor bloc (≥ audit-batch majority) colluding with one client |
| **Capability** | Controlling majority of votes in a batch; client submits a backdoored local model CID |
| **Protocol response today** | `finalizeEvaluation` approves a model when `eligible == true` AND `median >= passScore` (`DINTaskAuditor.sol:1247`). If the colluding bloc controls the majority, they set `eligible = true` and score ≥ `passScore`, overriding minority dissent. The `AuditorScoreDeviation` event is emitted when scores deviate beyond `s3DeviationThreshold` (`DINTaskAuditor.sol:1270`), but `s3SlashingEnabled = false` (`DINTaskAuditor.sol:148`) — no slash fires. Honest aggregators fold in whatever `approvedModelIndexes` returns without any on-chain check of model quality. |
| **Expected test outcome** | **KNOWN GAP** ([#38](https://github.com/InfiniteZeroFoundation/DevNet/issues/38)) — the test sets up a colluding auditor bloc, submits a poison-flagged model CID, asserts `AuditorScoreDeviation` is emitted with `exceedsThreshold = true`, and asserts no slash occurs. When S3 graduates from shadow mode this test must flip to `test_defended_`. |
| **Trust assumption** | S3 is deliberately shadow-mode during data-collection phase (`Developer/design/slashing-taxonomy.md` §S3); requires real-world threshold calibration before graduation. |

---

### Row 5 — T1 aggregator majority submits wrong CID

| Field | Value |
|---|---|
| **Attacker** | Majority of T1 aggregators in a batch (no auditor collusion needed) |
| **Capability** | Controls ≥ `T1_AGGREGATORS_PER_BATCH / 2 + 1` keys in one batch; submits a wrong CID |
| **Protocol response today** | The wrong CID wins the majority vote and is finalized. The honest dissenter who submitted the correct CID is slashed for `AGG_T1_BAD_CONSENSUS` (`DINTaskCoordinator.sol:963`). S4 dispute (`openDispute` → `lockDisputeSeed` → `settleRecomputation`) is the only remedy. Adjudication is `onlyOwner`. |
| **Expected test outcome** | **⚠ JUDGMENT CALL — flagged for Umer review.** Two possible readings: (a) **DEFENDED** under the owner-adjudicator trust assumption — owner upholds the dispute, original aggregators are slashed S4_INVALID_AGGREGATION, honest dissenter's bond is returned. (b) **KNOWN GAP** if the owner is also colluding (see Row 7). Proposed: mark DEFENDED with an explicit trust assumption that the owner is honest, and link Row 7 as the gap for the collusion case. |
| **Trust assumption** | "Owner is honest adjudicator (S4, pre-decentralization)" — see trust-assumptions section. |

---

### Row 6 — Cross-role dual-registration + owner batch-routing

| Field | Value |
|---|---|
| **Attacker** | One operator registered as both auditor and aggregator in the same GI; model owner grinds T1 batch assignment |
| **Capability** | Two keys (auditor + aggregator), both staking MIN_STAKE; owner mines a `block.timestamp` that routes the poisoned model into the colluding T1 batch (`_shuffleUintArray`, `DINTaskCoordinator.sol:621`) |
| **Protocol response today** | Nothing prevents dual-role registration; both `registerDINaggregator` and `registerDINAuditor` only check `isValidatorActive` and the concurrent-registration cap (`DINTaskCoordinator.sol:371-390`, `DINTaskAuditor.sol:188`). The batch-shuffle seed `block.timestamp + msg.sender` is owner-controllable for T1 batch assignment (distinct from the dispute seed which uses `lockDisputeSeed`). See #156 for the separate T1-shuffle randomness issue. |
| **Expected test outcome** | **KNOWN GAP** ([#180](https://github.com/InfiniteZeroFoundation/DevNet/issues/180), [#156](https://github.com/InfiniteZeroFoundation/DevNet/issues/156)) — the test registers one address in both contracts for the same GI and asserts it succeeds (gap confirmed), then asserts the owner can grind `block.timestamp` to place the colluding aggregator in the target batch. No slash fires for the registration itself. The "colluding aggregators skip outlier clipping" step is off-chain (model-dependent, not testable in Forge). |
| **Trust assumption** | None that defends this — gap pending #180 (role-separation guard) and #156 (stronger T1-shuffle seed). |

---

### Row 7 — Challenger right, owner rejects dispute

| Field | Value |
|---|---|
| **Attacker** | Model owner who is also, or is colluding with, the T1 aggregator majority |
| **Capability** | Owner calls `settleRecomputation(confirmed=false)` after a valid S4 dispute — original CID stood, challenger's bond is forfeited, no aggregators are slashed |
| **Protocol response today** | `settleRecomputation` is `onlyOwner` (`DINTaskCoordinator.sol:1281`). Owner is the sole adjudicator; no appeal exists on-chain. |
| **Expected test outcome** | **KNOWN GAP** ([#181](https://github.com/InfiniteZeroFoundation/DevNet/issues/181)) — the test opens a valid dispute, then has the owner call `settleRecomputation(false)`, and asserts the challenger's bond is forfeited and no aggregators are slashed. When #181 is resolved (decentralized adjudication) this test must flip. |
| **Trust assumption** | "Owner is honest adjudicator (S4, pre-decentralization)" — see trust-assumptions section. The gap is that this assumption can't be enforced on-chain. |

---

### Row 8 — Owner steering the dispute recomputation subgroup (BL-11)

| Field | Value |
|---|---|
| **Attacker** | Model owner who tries to steer which validators are assigned to the fresh subgroup in `settleRecomputation` |
| **Capability** | Owner controls when to call `lockDisputeSeed` and `settleRecomputation`; no control over block hash after `disputeSeedDelay` blocks |
| **Protocol response today** | PR #171 (`lockDisputeSeed`): after `openDispute`, a `seedBlock = block.number + disputeSeedDelay` (default: 7 blocks, `DINTaskCoordinator.sol:151`) is set. Anyone can call `lockDisputeSeed` once `block.number > seedBlock`; it reads `blockhash(seedBlock)` to fix the seed. The seed is then used by `_assignFreshSubgroup` to draw from the registered pool excluding the accused aggregators. The owner cannot control `blockhash(seedBlock)` without grinding 7+ blocks on Optimism PoS. |
| **Expected test outcome** | **DEFENDED** — the test advances 8 blocks, calls `lockDisputeSeed`, and asserts `_assignFreshSubgroup` draws a deterministic set based on the seed. Attempting to re-call `lockDisputeSeed` on a locked dispute reverts. A second call after an expired seed-window resets to `block.number + disputeSeedDelay` and re-locks on the new blockhash. |
| **Trust assumption** | "Optimism block proposer does not grind `blockhash(seedBlock)` — PoS randomness is sufficient for testnet" ([#178](https://github.com/InfiniteZeroFoundation/DevNet/issues/178) tracks upgrade to VRF for mainnet). |

---

### Row 9 — Reward manipulation: auditor submits inflated scores

| Field | Value |
|---|---|
| **Attacker** | Auditor submitting inflated scores to bias reward share toward a colluding client |
| **Capability** | One or more colluding auditors controlling < 50 % of votes in a batch; submit max scores for a target model |
| **Protocol response today** | `_medianOf` sorts scores and picks the middle value (`DINTaskAuditor.sol:821`). An auditor controlling < 50 % of votes cannot move the median to any value above or below the honest majority's range. A bloc controlling ≥ 50 % can set any median — but that is Sybil-grade and bounded by the Row 2 cost. `AuditorScoreDeviation` is emitted when deviation exceeds `s3DeviationThreshold`, but S3 is shadow-mode (Row 4). |
| **Expected test outcome** | **COST-BOUNDED** — the test verifies that a single colluding auditor (1 of 3) inflating a score cannot shift the median to the inflated value. A 2-of-3 colluding bloc can, but at `2 × MIN_STAKE` cost and `AuditorScoreDeviation` emitted. Test asserts median value and the event. |
| **Trust assumption** | `_medianOf` is correctly implemented (covered by `RewardEngine.t.sol`). |

---

### Row 10 — Duplicate-update gaming

| Field | Value |
|---|---|
| **Attacker** | Client submitting multiple local model updates in one GI to bias the global model |
| **Capability** | Client controls the content of their single `submitLocalModel` submission |
| **Protocol response today** | `clientHasSubmitted[_GI][msg.sender]` gate prevents double submission (`DINTaskAuditor.sol`). BlockFLow-style fold-in scoring (#39) is not yet implemented — no on-chain mechanism weights updates by client training-set size or penalizes duplicate-content submissions. |
| **Expected test outcome** | **Deferred** — depends on BlockFLow fold-in scoring (#39), which is not implemented. List in gaps-before-audit. No test in Part 2. |
| **Trust assumption** | — |

---

## Trust assumptions

These are the assumptions that DEFENDED rows depend on. A scenario marked DEFENDED is only actually defended if the corresponding assumption holds.

| ID | Assumption | DEFENDED rows that rely on it |
|---|---|---|
| TA-1 | **Owner is honest adjudicator (S4, pre-decentralization).** `settleRecomputation` is `onlyOwner`; no on-chain appeal exists. | Row 5 (T1 wrong CID via S4), Row 8 (subgroup steering) |
| TA-2 | **S5 recidivism counter is correctly implemented and called.** `slashPartial` in `DinValidatorStake` is the only path; each task contract must call it (not `slash()`) for liveness faults. | Row 3 |
| TA-3 | **Concurrent-registration cap is calibrated.** `capPerUnit` and `MIN_STAKE` must make seat capture prohibitively expensive relative to model rewards. | Rows 1, 2 |
| TA-4 | **Optimism block proposer does not grind `blockhash(seedBlock)`.** PoS finality on Optimism Sepolia provides sufficient entropy for the dispute seed for testnet. Mainnet requires VRF upgrade (#178). | Row 8 |
| TA-5 | **`_medianOf` is correctly implemented.** Covered by `RewardEngine.t.sol`; trusted as a unit invariant here. | Row 9 |

---

## Gaps before audit

These are KNOWN GAP rows that must be closed before a security audit can treat the attacked surface as defended.

| Gap | Tracking issue | Scenario | Condition to flip |
|---|---|---|---|
| S3 graduating from shadow mode | [#38](https://github.com/InfiniteZeroFoundation/DevNet/issues/38) | Row 4 (auditor bloc poisoned model) | `s3SlashingEnabled` set to `true` after threshold calibration |
| Dual-role registration guard | [#180](https://github.com/InfiniteZeroFoundation/DevNet/issues/180) | Row 6 (cross-role + owner routing) | `registerDINaggregator` / `registerDINAuditor` reject validators already registered in the other role for the same GI |
| Stronger T1-shuffle seed | [#156](https://github.com/InfiniteZeroFoundation/DevNet/issues/156) | Row 6 (owner batch-routing) | `_shuffleUintArray` replaced with commit-reveal or post-registration blockhash |
| Decentralized dispute adjudication | [#181](https://github.com/InfiniteZeroFoundation/DevNet/issues/181) | Row 7 (owner rejects valid dispute) | `settleRecomputation` gated by multi-sig, DAO committee, or optimistic fraud-proof |
| BlockFLow duplicate-update scoring | [#39](https://github.com/InfiniteZeroFoundation/DevNet/issues/39) | Row 10 (duplicate-update gaming) | BlockFLow fold-in scoring implemented |
| Mainnet VRF for dispute seed | [#178](https://github.com/InfiniteZeroFoundation/DevNet/issues/178) | Row 8 (trust assumption TA-4) | `lockDisputeSeed` upgraded to Chainlink VRF or multi-party commit-reveal |

---

## Judgment calls flagged for Umer review

1. **Row 5 — T1 wrong CID: DEFENDED or KNOWN GAP?**  
   Proposed: DEFENDED under TA-1, with Row 7 as the separate KNOWN GAP for the colluding-owner case. If Umer prefers treating these as one row and marking the whole scenario KNOWN GAP, the test in Part 2 becomes `test_knownGap_t1WrongCID` instead of `test_defended_t1WrongCID`.

2. **Row 6 — Dual-role registration: intended or gap?**  
   The code does not prevent it. Marked KNOWN GAP and issue #180 opened. If it is intentionally permitted (e.g. the concurrent-registration cap is the intended defence), issue #180 can be closed and the doc updated to reflect the trust assumption.
