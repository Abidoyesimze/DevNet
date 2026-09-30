# DINTaskCoordinator — Technical Documentation

> **File:** `foundry/src/DINTaskCoordinator.sol`
> **SPDX-License-Identifier:** UNLICENSED
> **Solidity:** `^0.8.28`

---

## 1. Overview

`DINTaskCoordinator` is the **central orchestration contract** for the DIN Protocol's federated learning workflow. It is the single entity that drives the 24-state Global Iteration (GI) lifecycle, coordinates between aggregators and the auditor contract, and executes slashing of misbehaving participants.

Responsibilities:
- **State machine management** — Advance `GIstate` through the full GI lifecycle (see `DINShared.md` §2 for the full `GIstates` table, including the commit-then-reveal evaluation phases).
- **Aggregator registration** — Accept active validators as aggregators for a GI.
- **Tier-1 and Tier-2 batch creation** — Form aggregation batches from approved local models.
- **Aggregation result collection** — Accept and vote on aggregated model CIDs.
- **Slashing** — Trigger auditor slashing on the paired `DINTaskAuditor` (see `DINTaskAuditor.md` §10 for the actual S1/S3 logic), and directly slash aggregators that failed to participate or submitted a non-consensus CID.

The contract is owned by the model owner (via `Ownable`) and delegates auditor operations to `DINTaskAuditor`.

---

## 2. Inheritance & Dependencies

| Component | Source | Purpose |
|-----------|--------|---------|
| `Ownable` | OpenZeppelin | Owner-restricted lifecycle transitions |
| `DINShared.sol` | Local | `GIstates` enum, cross-contract interfaces, error declarations |

---

## 3. State Variables

### 3.1 Core State

| Variable | Type | Visibility | Description |
|----------|------|-----------|-------------|
| `dinvalidatorStakeContract` | `IDinValidatorStake` | `public` | Validator stake contract — source of `isValidatorActive()` (registration/submission gating) and `minStake()` (aggregator slash amount, fetched dynamically, not cached) |
| `dinTaskAuditorContract` | `IDINTaskAuditor` | `public` | Auditor contract for delegation |
| `GI` | `uint` | `public` | Current Global Iteration counter (starts at 0, first active GI = 1) |
| `GIstate` | `GIstates` | `public` | Current lifecycle state |
| `genesisModelIpfsHash` | `bytes32` | `public` | IPFS hash of the genesis model, set once before GI 1 |

> **Note:** there is no `minStake` state variable on this contract. Aggregator registration and submissions are gated by `dinvalidatorStakeContract.isValidatorActive()`, and the aggregator slash amount is read live from `dinvalidatorStakeContract.minStake()` at slash time — neither is a value cached or configurable on `DINTaskCoordinator` itself.

### 3.2 Aggregator Registry

| Variable | Type | Description |
|----------|------|-------------|
| `dinAggregators` | `mapping(uint => address[])` | Registered aggregators per GI |
| `isDINAggregator` | `mapping(uint => mapping(address => bool))` | Membership check |

### 3.3 Tier-1 Batch State

| Variable | Type | Description |
|----------|------|-------------|
| `tier1Batches` | `mapping(uint => Tier1Batch[])` | T1 batches per GI |
| `isTier1Aggregator` | `mapping(uint => mapping(uint => mapping(address => bool)))` | GI → batchId → address → assigned |
| `t1SubmissionCID` | `mapping(uint => mapping(uint => mapping(address => bytes32)))` | Submitted CID per aggregator |
| `t1Submitted` | `mapping(uint => mapping(uint => mapping(address => bool)))` | Submission flag |
| `t1Votes` | `mapping(uint => mapping(uint => mapping(bytes32 => uint)))` | Vote count per CID |

### 3.4 Tier-2 Batch State

| Variable | Type | Description |
|----------|------|-------------|
| `tier2Batches` | `mapping(uint => Tier2Batch[])` | T2 batches per GI (always exactly 1) |
| `isTier2Aggregator` | `mapping(uint => mapping(uint => mapping(address => bool)))` | Assignment check |
| `t2SubmissionCID` | `mapping(uint => mapping(uint => mapping(address => bytes32)))` | Submitted CID |
| `t2Submitted` | `mapping(uint => mapping(uint => mapping(address => bool)))` | Submission flag |
| `t2Votes` | `mapping(uint => mapping(uint => mapping(bytes32 => uint)))` | Vote count per CID |
| `tier2Score` | `mapping(uint => uint)` | Final score recorded for a GI's T2 output |

---

## 4. Data Structures

### 4.1 `Tier1Batch`

```solidity
struct Tier1Batch {
    uint batchId;           // Unique within GI (sequential)
    address[] aggregators;  // Aggregators assigned to this batch
    uint[] modelIndexes;    // Indexes into approvedModels for this GI
    bool finalized;         // True after majority winner determined
    bytes32 finalCID;       // Winning aggregated model CID
}
```

### 4.2 `Tier2Batch`

```solidity
struct Tier2Batch {
    uint batchId;           // Always 0 (only one T2 batch)
    address[] aggregators;  // T2 aggregators
    bool finalized;
    bytes32 finalCID;       // Global winning aggregated CID
}
```

### 4.3 Aggregation Constants

```solidity
uint256 public constant T1_AGGREGATORS_PER_BATCH = 3;
uint256 public constant T1_MODELS_PER_BATCH = 3;
uint256 public constant MIN_T1_MODELS_PER_BATCH = 2;
```

---

## 5. Access Control

```
Ownable (model owner)
  ├── setDINTaskAuditorContract()
  ├── setDINTaskCoordinatorAsSlasher()
  ├── setDINTaskAuditorAsSlasher()
  ├── setGenesisModelIpfsHash()
  ├── startGI(uint, uint) / startGI(uint)
  ├── startDINaggregatorsRegistration()
  ├── closeDINaggregatorsRegistration()
  ├── startDINauditorsRegistration()
  ├── closeDINauditorsRegistration()
  ├── startLMsubmissions()
  ├── closeLMsubmissions()
  ├── createAuditorsBatches()
  ├── setTestDataAssignedFlag()
  ├── startLMsubmissionsEvaluation()          // opens commit phase
  ├── startLMsubmissionsEvaluationReveal()     // closes commit, opens reveal phase
  ├── closeLMsubmissionsEvaluation()
  ├── autoCreateTier1AndTier2()
  ├── startT1Aggregation()
  ├── finalizeT1Aggregation()
  ├── startT2Aggregation()
  ├── finalizeT2Aggregation()
  ├── slashAuditors()
  ├── slashAggregators()
  ├── setTier2Score()
  └── endGI()

Permissionless (with batch/GI guards)
  ├── registerDINaggregator()
  ├── submitT1Aggregation()
  └── submitT2Aggregation()
```

---

## 6. Initialization Sequence (Pre-GI Setup)

Before any GI can begin, a one-time setup must be completed:

```
State: [0] AwaitingDINTaskAuditorToBeSet
  → setDINTaskAuditorContract(auditorAddress)
State: [1] AwaitingDINTaskCoordinatorAsSlasher
  → (DAO calls DinCoordinator.addSlasherContract(taskCoordinatorAddress))
  → setDINTaskCoordinatorAsSlasher()    // verifies isSlasherContract(this) == true
State: [2] AwaitingDINTaskAuditorAsSlasher
  → (DAO calls DinCoordinator.addSlasherContract(taskAuditorAddress))
  → setDINTaskAuditorAsSlasher()        // verifies isSlasherContract(auditor) == true
State: [3] AwaitingGenesisModel
  → setGenesisModelIpfsHash(cid)
State: [4] GenesisModelCreated
```

---

## 7. GI Lifecycle Functions

### 7.1 `startGI`

```solidity
function startGI(uint _GI, uint score) public onlyOwner   // updates the pass score
function startGI(uint _GI) public onlyOwner                // keeps the existing pass score
```

Both overloads delegate to an internal `_startGI(_GI, score, updatePassScore)`:

1. Check `GIstate == GenesisModelCreated` or `GIstate == GIended` (allows repeat GIs).
2. Check `_GI == GI + 1` (must increment by exactly 1).
3. If called via the two-argument overload, call `dinTaskAuditorContract.updatePassScore(score)` — sets minimum median-score approval threshold for this GI. The one-argument overload skips this and simply reuses whatever pass score is already set on `DINTaskAuditor`.
4. Set `GIstate = GIstarted`, increment `GI`.

---

### 7.2 Aggregator Registration

```solidity
function registerDINaggregator(uint _GI) public
```

Permissionless (no `onlyCurrentGI` modifier — note: `isDINAggregator[_GI]` check uses the passed `_GI`).

1. Check `GIstate == DINaggregatorsRegistrationStarted`.
2. Check `dinvalidatorStakeContract.isValidatorActive(msg.sender)` (`TC_AggregatorNotActive` otherwise).
3. Check not already registered (`TC_AggregatorAlreadyRegistered`).
4. Push to `dinAggregators[_GI]`, set membership.
5. Emit `DINValidatorRegistered`.

---

### 7.3 Tier-1 and Tier-2 Batch Formation (`autoCreateTier1AndTier2`)

```solidity
function autoCreateTier1AndTier2(uint _GI) external onlyOwner onlyCurrentGI(_GI)
```

Called after LM evaluation closes (`LMSevaluationClosed`). Reverts with `TC_AggSeedNotLocked` unless `aggSeed[_GI]` is already locked via `lockAggSeed` (issue #156 H-2, task_240926_18 Part B — see the seed-lock subsection below).

**Algorithm:**

1. **Load aggregator pool:** filter the historical registration list `dinAggregators[_GI]` down to aggregators still `isValidatorActive` at call time (`_activeAggregatorPool`). Revert `TC_NotEnoughValidators` if the active count is below `T1_AGGREGATORS_PER_BATCH`.

2. **Shuffle aggregators (Fisher-Yates, `pure`):**
   ```
   j = keccak256(keccak256(aggSeed[_GI], "AGG_ADDR"), i, arr.length) % (i+1)
   ```

3. **Collect approved model indexes:** Calls `dinTaskAuditorContract.approvedModelIndexes(_GI)`. Revert `TC_NotEnoughApprovedModels` if fewer than `T1_MODELS_PER_BATCH`.

4. **Shuffle model indexes (Fisher-Yates, memory, `pure`):**
   ```
   j = keccak256(keccak256(aggSeed[_GI], "AGG_IDX"), i, arr.length) % (i+1)
   ```

5. **Greedy T1 batch creation:**
   ```
   while vPtr + T1_AGGREGATORS_PER_BATCH <= vLen
         AND (enough models for a full or minimum-size batch):
       T1 batch:
         aggregators = valPool[vPtr .. vPtr+2]
         modelsToAssign = min(T1_MODELS_PER_BATCH, remaining)
         modelIndexes = modelIdx[mPtr .. mPtr+modelsToAssign-1]
       vPtr += 3, mPtr += modelsToAssign
   ```

6. **T2 batch creation:** If `vLen - vPtr >= T1_AGGREGATORS_PER_BATCH`, create exactly one T2 batch with `valPool[vPtr .. vPtr+2]`. T2 batch always has `batchId = 0`.

7. Set `GIstate = T1nT2Bcreated`.

---

### 7.4 T1 Aggregation

**Submit:**
```solidity
function submitT1Aggregation(uint _GI, uint _batchId, bytes32 _aggregationCID) external
```
- Validates sender is assigned T1 aggregator for the batch (`TC_NotBatchAggregator`).
- Validates sender is still `isValidatorActive` (`TC_AggregatorNotActive`).
- One submission per aggregator (`TC_AlreadySubmitted`).
- Tallies votes: `t1Votes[_GI][_batchId][_aggregationCID]++`.

**Finalize:**
```solidity
function finalizeT1Aggregation(uint _GI) external onlyOwner
```
For each T1 batch, determines the winning CID by plurality (most votes):
```
For each aggregator in batch:
    if submitted:
        cid = t1SubmissionCID[...][aggregator]
        if t1Votes[...][cid] > maxVotes:
            maxVotes = t1Votes[...][cid]
            winningCID = cid
b.finalized = true
b.finalCID = winningCID
```
Reverts `TC_NoSubmissions` if no CID was submitted for a batch.

Sets `GIstate = T1AggregationDone`.

---

### 7.5 T2 Aggregation

Identical pattern to T1 (including the `isValidatorActive` check on submit) but operates on `tier2Batches`. Only one batch exists (batchId = 0). Sets `GIstate = T2AggregationDone`.

---

## 8. Slashing Mechanism

### 8.1 `slashAuditors`

```solidity
function slashAuditors(uint _GI) external onlyOwner onlyCurrentGI(_GI)
```

State requirement: `T2AggregationDone`.

This is a **thin delegation wrapper**: it calls `dinTaskAuditorContract.slashAuditors(_GI)` (reverting with `TC_FailedToSlashAuditors` if that returns `false`) and then advances `GIstate = AuditorsSlashed`. The actual slashing logic — S1 (missed vote) always active, S3 (score-deviation) gated behind `s3SlashingEnabled` — lives entirely on `DINTaskAuditor`; see `DINTaskAuditor.md` §10 for the full algorithm.

### 8.2 `slashAggregators`

```solidity
function slashAggregators(uint _GI) external onlyOwner onlyCurrentGI(_GI)
```

State requirement: `AuditorsSlashed`.

**Algorithm:**

```
slashAmount = dinvalidatorStakeContract.minStake()   // read live, not cached

For each T1 batch:
  For each aggregator in batch:
    submitted = t1Submitted[GI][batchId][aggregator]
    submittedMatching = (submitted AND t1SubmissionCID[...] == b.finalCID)
    reason = submitted ? (submittedMatching ? — : "AGG_T1_BAD_CONSENSUS") : "AGG_T1_NO_SUBMISSION"
    if NOT submitted OR NOT submittedMatching:
      actual = dinvalidatorStakeContract.slash(aggregator, slashAmount, reason)
      emit AggregatorSlashed(GI, batchId, aggregator, reason, slashAmount, actual)

For each T2 batch:
  Same logic using t2Submitted, t2SubmissionCID, b.finalCID, reasons "AGG_T2_NO_SUBMISSION" / "AGG_T2_BAD_CONSENSUS"
```

**Slash condition:** An aggregator is slashed if they either:
- Did not submit any CID (`AGG_T1_NO_SUBMISSION` / `AGG_T2_NO_SUBMISSION`), OR
- Submitted a CID that did not match the winning (plurality) CID (`AGG_T1_BAD_CONSENSUS` / `AGG_T2_BAD_CONSENSUS`).

**Slash amount:** `dinvalidatorStakeContract.minStake()` at call time — fetched live from the stake contract, not a value stored on `DINTaskCoordinator`. `IDinValidatorStake.slash()` returns the amount actually deducted, which is recorded in the `AggregatorSlashed` event alongside the requested amount (they can differ, e.g. if the aggregator's remaining stake is below `slashAmount`).

Sets `GIstate = AggregatorsSlashed`.

---

## 9. Tier-2 Score

```solidity
function setTier2Score(uint _GI, uint _score) external onlyOwner onlyCurrentGI(_GI)
function getTier2Score(uint _GI) external view returns (uint)
```

Records an off-chain computed performance score for the T2 aggregation result. Can be set during `T2AggregationDone` or `GenesisModelCreated` states. This is a metadata field — it does not affect slashing.

---

## 10. GI Termination

```solidity
function endGI(uint _GI) external onlyOwner onlyCurrentGI(_GI)
```

State requirement: `AggregatorsSlashed`. Sets `GIstate = GIended`.

After `endGI`, a new GI can be started via `startGI(_GI+1, newPassScore)` or `startGI(_GI+1)`.

---

## 11. Shuffling (PRNG Details)

Two internal shuffle helpers (`pure`, taking an explicit `bytes32 seed`) mirror those in `DINTaskAuditor`, and are applied to the *active-filtered* aggregator pool (`_activeAggregatorPool`), not the raw historical registration list:

| Function | Target | Entropy |
|----------|--------|---------|
| `_shuffleAddressArray` | Active aggregator pool | `keccak256(seed, "AGG_ADDR")` (`autoCreateTier1AndTier2`) or the dispute seed's own domain tag (`_assignFreshSubgroup`) |
| `_shuffleUintArray` (memory) | Model index pool | `keccak256(seed, "AGG_IDX")` |

Both use Fisher-Yates algorithm. `aggSeed[_GI]` / `auditSeed[_GI]` (§11.1) replaced `blockhash(block.number - 1)` / `block.timestamp + msg.sender` as of issue #156 H-2 (task_240926_18 Part B) — see Security Considerations below for what the fix does and doesn't close.

### 11.1 Batch-Assignment Seed Lock

`autoCreateTier1AndTier2` and `createAuditorsBatches` (delegated to `DINTaskAuditor`, passing the locked seed across the interface) each require their own ungrindable seed to already be locked, using the same future-block-seed + permissionless-lock pattern as the dispute seed (`Dispute.seed`/`Dispute.seedBlock`, `lockDisputeSeed`):

- **Anchor:** `closeLMsubmissionsEvaluation` sets `aggSeedBlock[_GI] = block.number + disputeSeedDelay` (T1/T2); `closeLMsubmissions` sets `auditSeedBlock[_GI]` the same way (auditor batches). `disputeSeedDelay` is reused rather than adding a second delay parameter — same owner-controlled-transition trust assumption as the dispute seed.
- **Lock:** `lockAggSeed(uint _GI)` / `lockAuditSeed(uint _GI)`, callable by **anyone**, once `block.number > seedBlock`. Stores `seed = keccak256(blockhash(seedBlock), _GI, "AGG"/"AUD")` and emits `AggSeedLocked`/`AuditSeedLocked`. If `blockhash(seedBlock) == 0` (more than 256 blocks passed), re-anchors instead (`seedBlock = block.number + disputeSeedDelay`, `AggSeedReanchored`/`AuditSeedReanchored`) rather than storing a zero-derived seed.
- **Gate:** `autoCreateTier1AndTier2` reverts `TC_AggSeedNotLocked` and `createAuditorsBatches` reverts `TC_AuditSeedNotLocked` unless `aggSeed[_GI]`/`auditSeed[_GI]` is already non-zero. `DINTaskAuditor.createAuditorsBatches(uint, bytes32)` independently rejects a zero seed too (`TA_AuditSeedNotLocked`), defense-in-depth on top of the coordinator's own check.

**Residual trust and gaps** (raised in the PR #191 review, not fixed by this mechanism; tracked as BL-26 in [`Developer/BACK_LOG.md`](../../../Developer/BACK_LOG.md)):
- **Sequencer trust:** `blockhash` is sequencer-produced on OP Stack, so this design trusts the sequencer not to grind — same caveat as the dispute seed. VRF is the mainnet-grade follow-up (issue #178).
- **Re-roll by declining to lock:** once `seedBlock` is mined, its hash (and therefore the resulting shuffle) is computable off-chain by anyone watching. The model owner can simply not call `lock…Seed` if they dislike the preview, wait out the 256-block window, and get a fresh anchor on the next lock call — repeatable. The permissionless lock only protects against this if another party locks first.
- **Post-lock pool reshaping:** `_activeAggregatorPool`/`_activeAuditorPool` are evaluated at `autoCreateTier1AndTier2`/`createAuditorsBatches` call time, *after* the seed is already public. A validator can unstake between the lock and the create call to remove themselves from the pool, which re-shuffles everyone else's assignment (Fisher-Yates re-rolls on any pool-size change) — an attacker with several registered addresses can compute all subset outcomes off-chain and unstake whichever produces the batch they want.

---

## 12. Events

| Event | Emitted When |
|-------|--------------|
| `DINValidatorRegistered(GI, validator)` | Aggregator registers |
| `Tier1BatchAuto(GI, batchId)` | T1 batch created |
| `Tier2BatchAuto(GI, batchId)` | T2 batch created |
| `AggregatorSlashed(GI, batchId, aggregator, reason, requested, actual)` | Aggregator slashed in `slashAggregators` (T1 or T2) |
| `AggSeedLocked(GI, seed)` | `lockAggSeed` locks the T1/T2 batch-assignment seed |
| `AggSeedReanchored(GI, newSeedBlock)` | `lockAggSeed` re-anchors after the 256-block `blockhash` window is missed |
| `AuditSeedLocked(GI, seed)` | `lockAuditSeed` locks the auditor-batch seed |
| `AuditSeedReanchored(GI, newSeedBlock)` | `lockAuditSeed` re-anchors after the 256-block `blockhash` window is missed |

---

## 13. Security Considerations

| Risk | Mitigation / Status |
|------|---------------------|
| Unauthorized state transitions | All owner functions guarded by `onlyOwner` |
| Wrong GI operations | `onlyCurrentGI` modifier on most functions |
| Weak PRNG for batch assignment | **Fixed** (issue #156 H-2, task_240926_18 Part B): `blockhash(block.number - 1)`/`block.timestamp` replaced by the locked, future-block `aggSeed`/`auditSeed` (§11.1). Residual: sequencer trust, a re-roll available to a model owner who declines to lock, and post-lock pool reshaping via unstaking — see §11.1's residual list. VRF remains the mainnet-grade follow-up (issue #178) |
| Auditor slashing | Implemented on `DINTaskAuditor` (S1 always active, S3 shadow-mode by default) and triggered here via delegation — see `DINTaskAuditor.md` §10 |
| Aggregator collusion (submit same wrong CID) | Plurality voting means 2-of-3 colluding aggregators win; no quorum threshold — design risk |
| No slash appeal mechanism | Slashed aggregators cannot challenge the decision on-chain |
| Aggregator/auditor activity checks depend on `DinValidatorStake` | Both registration and per-round submissions re-check `isValidatorActive` live; an address deactivated mid-GI is excluded from the *next* active-pool filter (batch formation) but a submission already made before deactivation still counts |

---

## 14. Interactions with Other Contracts

```
DINTaskCoordinator
  ├── reads  → DinValidatorStake.isValidatorActive()   [aggregator registration, T1/T2 submission, active-pool filtering in autoCreateTier1AndTier2]
  ├── reads  → DinValidatorStake.isSlasherContract()   [coordinator/auditor slasher checks]
  ├── reads  → DinValidatorStake.minStake()            [slashAggregators — slash amount, read live]
  ├── calls  → DinValidatorStake.slash()               [slashAggregators]
  ├── calls  → DINTaskAuditor.updatePassScore()        [startGI(uint, uint) overload]
  ├── calls  → DINTaskAuditor.createAuditorsBatches()  [createAuditorsBatches]
  ├── calls  → DINTaskAuditor.setTestDataAssignedFlag() [setTestDataAssignedFlag]
  ├── calls  → DINTaskAuditor.finalizeEvaluation()     [closeLMsubmissionsEvaluation]
  ├── calls  → DINTaskAuditor.slashAuditors()          [slashAuditors]
  └── reads  → DINTaskAuditor.approvedModelIndexes()   [autoCreateTier1AndTier2]
```

---

## 15. Known Limitations & Future Work

- Aggregator slashing is plurality-based: a 2-of-3 colluding majority wins without any cryptographic verification of the aggregated model.
- No on-chain reward distribution to aggregators — the T2 score is informational only.
- No mechanism to recover from a stalled GI (e.g., if T1 never reaches submissions).
- T2 always produces exactly one batch; no fallback if insufficient aggregators remain after T1 assignment.
- The commit-then-reveal evaluation phase (`LMSevaluationStarted` → `LMSevaluationRevealStarted` → `LMSevaluationClosed`) adds an explicit owner-driven step (`startLMsubmissionsEvaluationReveal`) between commit and reveal; forgetting to call it simply stalls the GI (no reveal is accepted) rather than corrupting any state, but it is one more manual step in the model-owner workflow than the pre-commit-reveal design had.
