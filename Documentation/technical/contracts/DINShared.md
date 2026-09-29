# DINShared — Technical Documentation

> **File:** `foundry/src/DINShared.sol`
> **SPDX-License-Identifier:** UNLICENSED
> **Solidity:** `^0.8.28`

---

## 1. Overview

`DINShared.sol` is a **shared type library** for the DIN Protocol. It is not a deployable contract — it contains no constructor, no state variables, and no functions. It is imported by both `DINTaskCoordinator` and `DINTaskAuditor` (and any future protocol contracts) to ensure they share:

1. The `GIstates` enum — the canonical lifecycle state machine for a Global Iteration.
2. Cross-contract interfaces (`IDinValidatorStake`, `IDINTaskCoordinator`, `IDINTaskAuditor`).
3. All custom error declarations for both `DINTaskAuditor` (`TA_*`) and `DINTaskCoordinator` (`TC_*`).

Centralising these definitions prevents ABI drift between contracts and makes the state machine a single source of truth.

---

## 2. Global Iteration State Machine

### 2.1 `GIstates` Enum

The `GIstates` enum defines every discrete state a Global Iteration (GI) can occupy, in sequential order. The `DINTaskCoordinator` transitions through these states in a strictly enforced linear progression.

```
Value  State Name                          Description
─────  ──────────────────────────────────  ────────────────────────────────────────────────────────
  0    AwaitingDINTaskAuditorToBeSet       Initial state after DINTaskCoordinator deployment.
  1    AwaitingDINTaskCoordinatorAsSlasher TaskAuditor has been set; coordinator not yet slasher.
  2    AwaitingDINTaskAuditorAsSlasher     Coordinator is slasher; auditor not yet slasher.
  3    AwaitingGenesisModel                Both contracts are slashers; genesis model not yet set.
  4    GenesisModelCreated                 Genesis model IPFS hash has been recorded.
  5    GIstarted                           A new GI has been incremented and started.
  6    DINaggregatorsRegistrationStarted   Aggregator registration window is open.
  7    DINaggregatorsRegistrationClosed    Aggregator registration window is closed.
  8    DINauditorsRegistrationStarted      Auditor registration window is open.
  9    DINauditorsRegistrationClosed       Auditor registration window is closed.
 10    LMSstarted                          Local Model Submission window is open.
 11    LMSclosed                           Local Model Submission window is closed.
 12    AuditorsBatchesCreated              Audit batches have been formed.
 13    LMSevaluationStarted                Commit phase: auditors submit hidden score/vote commitments via `commitAuditScore`.
 14    LMSevaluationRevealStarted          Reveal phase: auditors reveal (score, vote, salt) via `revealAuditScore`; eligibility and median scoring are computed from revealed values only.
 15    LMSevaluationClosed                 Evaluation finalized; approved models identified.
 16    T1nT2Bcreated                       Tier-1 and Tier-2 aggregation batches formed.
 17    T1AggregationStarted                Commit phase: Tier-1 aggregators submit hidden CID commitments via `commitT1Aggregation`.
 18    T1AggregationRevealStarted          Reveal phase: Tier-1 aggregators reveal (cid, salt) via `revealT1Aggregation`; only revealed CIDs count toward finalization.
 19    T1AggregationDone                   Tier-1 finalized; winning CIDs per batch recorded.
 20    T2AggregationStarted                Commit phase: Tier-2 aggregators submit hidden CID commitments via `commitT2Aggregation`.
 21    T2AggregationRevealStarted          Reveal phase: Tier-2 aggregators reveal (cid, salt) via `revealT2Aggregation`; only revealed CIDs count toward finalization.
 22    T2AggregationDone                   Tier-2 finalized; global winning CID recorded.
 23    AuditorsSlashed                     Auditor slashing phase executed.
 24    AggregatorsSlashed                  Aggregator slashing phase executed.
 25    GIended                             GI is complete; system is ready for next GI.
```

> **Ordinal note:** `LMSevaluationRevealStarted` (commit-then-reveal auditor scoring, task_210726_6 §2a) sits between `LMSevaluationStarted` and `LMSevaluationClosed` at ordinal 14. `T1AggregationRevealStarted` and `T2AggregationRevealStarted` (commit-then-reveal T1/T2 aggregation, issue #156 M-1, task_240926_18 Part C) sit at ordinals 18 and 21 respectively, immediately after their corresponding commit-phase state — same insert-in-lifecycle-position precedent, not appended. Each insertion shifts every later ordinal by +1 relative to the prior numbering. `dincli/cli/utils.py`'s `states`/`stateDescription` positional mirrors (indexed by this same raw ordinal) have been updated to match — see `dincli/cli/utils.py`'s `states`/`stateDescription` lists.

### 2.2 State Transition Diagram

```
[0] AwaitingDINTaskAuditorToBeSet
        │ setDINTaskAuditorContract()
        ▼
[1] AwaitingDINTaskCoordinatorAsSlasher
        │ setDINTaskCoordinatorAsSlasher()
        ▼
[2] AwaitingDINTaskAuditorAsSlasher
        │ setDINTaskAuditorAsSlasher()
        ▼
[3] AwaitingGenesisModel
        │ setGenesisModelIpfsHash()
        ▼
[4] GenesisModelCreated ◄──────────────────────────────── [25] GIended
        │ startGI()                                               ▲
        ▼                                                         │ endGI()
[5] GIstarted                                             [24] AggregatorsSlashed
        │ startDINaggregatorsRegistration()                       ▲
        ▼                                                         │ slashAggregators()
[6] DINaggregatorsRegistrationStarted               [23] AuditorsSlashed
        │ closeDINaggregatorsRegistration()                       ▲
        ▼                                                         │ slashAuditors()
[7] DINaggregatorsRegistrationClosed                [22] T2AggregationDone
        │ startDINauditorsRegistration()                          ▲
        ▼                                                         │ finalizeT2Aggregation()
[8] DINauditorsRegistrationStarted                  [21] T2AggregationRevealStarted
        │ closeDINauditorsRegistration()                          ▲
        ▼                                                         │ startT2AggregationReveal()
[9] DINauditorsRegistrationClosed                   [20] T2AggregationStarted
        │ startLMsubmissions()                                    ▲
        ▼                                                         │ startT2Aggregation()
[10] LMSstarted                                     [19] T1AggregationDone
        │ closeLMsubmissions()                                    ▲
        ▼                                                         │ finalizeT1Aggregation()
[11] LMSclosed                                      [18] T1AggregationRevealStarted
        │ createAuditorsBatches()                                 ▲
        ▼                                                         │ startT1AggregationReveal()
[12] AuditorsBatchesCreated                         [17] T1AggregationStarted
        │ startLMsubmissionsEvaluation()                          ▲
        ▼                                                         │ startT1Aggregation()
[13] LMSevaluationStarted                           [16] T1nT2Bcreated
        │ (auditors: commitAuditScore, commit phase)               ▲
        └──────────── startLMsubmissionsEvaluationReveal() ────────┤ autoCreateTier1AndTier2()
                       (auditors: revealAuditScore, reveal phase)  │
                                                         [15] LMSevaluationClosed
                                                                    ▲
                                                                    │ closeLMsubmissionsEvaluation()
                                                         [14] LMSevaluationRevealStarted
```

T1/T2 aggregation submissions follow the same commit-then-reveal shape as LMS evaluation above: `commitT1Aggregation`/`commitT2Aggregation` during the `*AggregationStarted` (commit) state, then the model owner calls `startT1AggregationReveal`/`startT2AggregationReveal` to open `*AggregationRevealStarted`, during which aggregators call `revealT1Aggregation`/`revealT2Aggregation`. Only revealed CIDs are counted by `finalizeT1Aggregation`/`finalizeT2Aggregation`; a committed-but-never-revealed aggregator is excluded from finalization and remains slashable via `slashAggregators`' existing "no submission" (S2) check (issue #156 M-1, task_240926_18 Part C).

---

## 3. Cross-Contract Interfaces

### 3.1 `IDinValidatorStake`

```solidity
interface IDinValidatorStake {
    function getStake(address validator) external view returns (uint256);
    function minStake() external view returns (uint256);
    function isValidatorActive(address validator) external view returns (bool);
    function slash(
        address validator,
        uint256 amount,
        bytes32 reason
    ) external returns (uint256);
    function isSlasherContract(address slasherContract) external view returns (bool);
}
```

Used by: `DINTaskCoordinator`, `DINTaskAuditor`

| Method | Purpose |
|--------|---------|
| `getStake` | Check if a registrant has sufficient stake before accepting registration |
| `minStake` | Minimum stake threshold a registrant/auditor/aggregator must be at or above |
| `isValidatorActive` | Checked on every `commitAuditScore`/`revealAuditScore` call (`TA_AuditorNotActive`) and aggregator registration (`TC_AggregatorNotActive`) |
| `slash` | Penalise a misbehaving auditor or aggregator, tagged with a `bytes32 reason`; returns the amount actually slashed |
| `isSlasherContract` | Verify a contract is registered as a slasher (used during model registration) |

### 3.2 `IDINTaskCoordinator`

```solidity
interface IDINTaskCoordinator {
    function GI() external view returns (uint256);
    function GIstate() external view returns (GIstates);
}
```

Used by: `DINTaskAuditor`

| Method | Purpose |
|--------|---------|
| `GI()` | Read the current Global Iteration counter for validation in modifiers |
| `GIstate()` | Check the current lifecycle state to gate operations |

### 3.3 `IDINTaskAuditor`

```solidity
interface IDINTaskAuditor {
    function createAuditorsBatches(uint _GI) external returns (bool);
    function setTestDataAssignedFlag(uint _GI, bool flag) external;
    function finalizeEvaluation(uint _GI) external returns (bool);
    function slashAuditors(uint _GI) external returns (bool);
    function approvedModelIndexes(uint _GI) external view returns (uint[] memory);
    function updatePassScore(uint256 newPassScore) external;
}
```

Used by: `DINTaskCoordinator`

| Method | Purpose |
|--------|---------|
| `createAuditorsBatches` | Called by coordinator to trigger batch formation in auditor contract |
| `setTestDataAssignedFlag` | Signals that test datasets have been distributed to batches |
| `finalizeEvaluation` | Computes final median scores and approval status for all submitted models; reverts unless `GIstate == LMSevaluationRevealStarted` |
| `slashAuditors` | Called by coordinator once `GIstate == T2AggregationDone`; slashes auditors who missed their vote, then coordinator transitions to `AuditorsSlashed` |
| `approvedModelIndexes` | Returns indexes of models that passed evaluation (used for T1/T2 batch formation) |
| `updatePassScore` | Sets the minimum median score required for model approval (called at start of each GI) |

---

## 4. Custom Error Catalogue

### 4.1 Commit-Then-Reveal Auditor Scoring (task_210726_6 §2a–2b)

| Error | Description |
|-------|-------------|
| `TA_CommitPhaseNotOpen` | `commitAuditScore` called while `GIstate != LMSevaluationStarted` |
| `TA_AlreadyCommitted` | Auditor has already committed a score for this `(gi, batchId, modelIndex)` |
| `TA_EmptyCommitHash` | `commitHash` argument is `bytes32(0)` |
| `TA_RevealPhaseNotOpen` | `revealAuditScore` called while `GIstate != LMSevaluationRevealStarted` |
| `TA_NoCommitFound` | No prior `commitAuditScore` recorded for this auditor/model — reveal without a commit |
| `TA_RevealHashMismatch` | `keccak256(abi.encodePacked(score, vote, salt))` does not match the stored commit hash |
| `TC_RevealCannotBeStarted` | `startLMsubmissionsEvaluationReveal` called while `GIstate != LMSevaluationStarted` |
| `TA_EncryptedKeyCountMismatch` | `assignAuditTestDataset`'s `encryptedKeys` array length does not match the batch's auditor count |

### 4.2 DINTaskAuditor Errors (`TA_*`)

| Error | Description |
|-------|-------------|
| `TA_NotTaskCoordinator` | Function restricted to the TaskCoordinator was called by another address |
| `TA_AmountMustBePositive` | Deposit or reward amount is zero |
| `TA_InvalidPassScore` | Pass score set outside 0–100 range |
| `TA_AuditorRegistrationNotOpen` | Registration attempted outside registration window |
| `TA_WrongGI` | Global Iteration mismatch |
| `TA_AuditorAlreadyRegistered` | Duplicate auditor registration for same GI |
| `TA_InsufficientStake` | Auditor's stake below minimum threshold |
| `TA_LMSubmissionsNotOpen` | Local model submission attempted outside submission window |
| `TA_AlreadySubmitted` | Client has already submitted a model this GI |
| `TA_MaxLMSubmissionsReached` | Submission count reached `MAX_LM_SUBMISSIONS` (10,000) |
| `TA_NotEnoughAuditors` | Too few auditors to form even one batch |
| `TA_CannotCreateAuditorsBatches` | State is not `LMSclosed` |
| `TA_BatchNotFound` | Batch ID query out of bounds |
| `TA_BatchDoesNotExist` | Batch ID >= batch array length |
| `TA_BatchIDMismatch` | Internal sanity check failure on batch ID |
| `TA_CannotSetTestDataAssignedFlag` | State is not `AuditorsBatchesCreated` |
| `TA_FlagMustBeTrue` | `setTestDataAssignedFlag` called with `flag = false` |
| `TA_FlagAlreadySet` | Flag was already set for this GI |
| `TA_NotAssignedAuditor` | Score commit/reveal from auditor not assigned to the batch |
| `TA_InvalidModelIndex` | Model index not assigned to this batch |
| `TA_CannotSetAuditScore` | Declared but currently unused — dead code left over from the pre-commit-reveal `setAuditScorenEligibility`, which this replaced with `commitAuditScore`/`revealAuditScore`. |
| `TA_ScoreOutOfRange` | Score > 100 (checked at reveal time) |
| `TA_AlreadyVoted` | Auditor has already revealed a score for this model |
| `TA_CannotFinalizeEvaluation` | State is not `LMSevaluationRevealStarted` |
| `TA_AuditorNotActive` | Auditor's `DinValidatorStake.isValidatorActive()` is false — checked on both commit and reveal |
| `TA_InvalidDeviationThreshold` | S3 deviation threshold set outside 0–100 range |
| `TA_EmptyScoreSet` | `_medianOf` called with zero scores to compute a median over |

### 4.3 DINTaskCoordinator Errors (`TC_*`)

| Error | Description |
|-------|-------------|
| `TC_TaskAuditorContractCannotBeSet` | Task auditor set attempted in wrong state |
| `TC_CoordinatorCannotBeSetAsSlasher` | Set-slasher called in wrong state |
| `TC_CoordinatorIsNotSlasher` | Coordinator not in `DinValidatorStake.slasherContracts` |
| `TC_AuditorCannotBeSetAsSlasher` | Auditor slasher set called in wrong state |
| `TC_AuditorIsNotSlasher` | Auditor not in `DinValidatorStake.slasherContracts` |
| `TC_GenesisModelHashCannotBeSet` | Genesis hash set in wrong state |
| `TC_GICannotBeStarted` | `startGI` called in wrong state |
| `TC_WrongGI` | GI index argument does not match current `GI` counter |
| `TC_AggregatorsRegistrationCannotBeStarted` | Registration start called in wrong state |
| `TC_AggregatorsRegistrationNotOpen` | Aggregator registration in wrong state |
| `TC_InsufficientStake` | Aggregator stake below threshold |
| `TC_AggregatorAlreadyRegistered` | Duplicate aggregator registration |
| `TC_AggregatorsRegistrationCannotBeFinished` | Close called in wrong state |
| `TC_AuditorsRegistrationCannotBeStarted` | Auditor registration start in wrong state |
| `TC_AuditorsRegistrationCannotBeFinished` | Auditor registration close in wrong state |
| `TC_LMSubmissionsCannotBeStarted` | LM submission window start in wrong state |
| `TC_LMSubmissionsNotStarted` | LM submission close when not started |
| `TC_LMEvalCannotBeStarted` | Reused by two functions: `createAuditorsBatches` when state is not `LMSclosed`, and `startLMsubmissionsEvaluation` (opens the commit phase) when state is not `AuditorsBatchesCreated` |
| `TC_LMEvalCannotBeFinished` | `closeLMsubmissionsEvaluation` called when state is not `LMSevaluationRevealStarted` |
| `TC_FailedToCreateAuditorsBatches` | `createAuditorsBatches` returned false |
| `TC_CannotSetTestDataAssignedFlag` | Test data flag set in wrong state |
| `TC_EvalPhaseNotClosed` | T1/T2 batch creation before evaluation close |
| `TC_NotEnoughValidators` | Too few aggregators for T1 batches |
| `TC_NotEnoughApprovedModels` | Fewer than `T1_MODELS_PER_BATCH` models approved |
| `TC_BatchNotFound` | Tier-1 batch ID out of bounds |
| `TC_OnlyOneTier2Batch` | Tier-2 batch ID != 0 |
| `TC_NotReadyForT1Aggregation` | T1 start in wrong state |
| `TC_T1AggregationNotStarted` | Submission or finalize called before T1 start |
| `TC_InvalidBatch` | Batch ID >= tier1Batches length |
| `TC_NotBatchAggregator` | Submitter not assigned to the batch |
| `TC_AlreadySubmitted` | Aggregator has already submitted for this batch |
| `TC_NoSubmissions` | No CIDs were submitted; cannot determine winner |
| `TC_NotReadyToFinalizeT1` | T1 finalize called in wrong state |
| `TC_NotReadyForT2Aggregation` | T2 start in wrong state |
| `TC_T2AggregationNotStarted` | T2 submission or finalize called before T2 start |
| `TC_NotReadyToFinalizeT2` | T2 finalize called in wrong state |
| `TC_NotReadyToSlashAuditors` | Auditor slash called before T2 done |
| `TC_NotReadyToSlashAggregators` | Aggregator slash called before auditors slashed |
| `TC_NotReadyToSetTier2Score` | Tier-2 score set in wrong state |
| `TC_NotReadyToEndGI` | `endGI` called before aggregators slashed |
| `TC_FailedToFinalizeEvaluation` | `finalizeEvaluation` returned false |
| `TC_AggregatorNotActive` | Aggregator's `DinValidatorStake.isValidatorActive()` is false |
| `TC_FailedToSlashAuditors` | `DINTaskAuditor.slashAuditors()` returned false |

---

## 5. Design Rationale

### Why a Shared File?

Both `DINTaskCoordinator` and `DINTaskAuditor` need to read each other's state (via interfaces) and react to shared lifecycle states (via `GIstates`). Without `DINShared.sol`:
- The enum would be duplicated across contracts, risking value drift.
- Interface definitions could go stale when one contract is updated without updating the other.

### Error Namespacing

The `TA_` and `TC_` prefixes make it immediately clear in stack traces and event logs which contract emitted an error, even when both contracts are interacting in the same transaction. `TC_RevealCannotBeStarted` is the one exception worth calling out: it's grouped with the commit-then-reveal errors in the source (§4.1 above) because it gates the coordinator-side phase transition those errors depend on, but it keeps the `TC_` prefix since it's the coordinator, not the auditor, that reverts with it.

### Commit-Then-Reveal Auditor Scoring

`LMSevaluationStarted` and `LMSevaluationRevealStarted` split what was previously a single evaluation phase into two: auditors first commit `keccak256(score, vote, salt)` (hiding their vote from other auditors until everyone has committed), then, once the model owner closes the commit window via `DINTaskCoordinator.startLMsubmissionsEvaluationReveal`, reveal the underlying `(score, vote, salt)` for it to be counted. An auditor who commits but never reveals is simply excluded from quorum/median counting, and remains slashable via the existing "missed vote" check in `slashAuditors` — no separate non-reveal handling needed.
