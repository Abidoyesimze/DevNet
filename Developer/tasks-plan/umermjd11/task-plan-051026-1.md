# Task Plan: DevNet 2.0 Launch Readiness: `DINTaskAuditor` Size (#201 A4), Dual-Role Guard (#180), Cross-Model S5 (#193), dincli Task-Contract Gaps (BL-27/BL-28), Public Docs Drift

**ID:** task-plan-051026-1
**Author:** Umer Majeed (@umermjd11)
**Reviewer:** @umeradl
**Created:** 2026-10-05
**Status:** Pending review
**Proposed dates:** Oct 6 – Oct 16, 2026
**Repo:** https://github.com/InfiniteZeroFoundation/DevNet
**Base branch:** `develop`. The plan was written against commit `740a613` (2026-10-05, after PR #215 and its follow-up). Line numbers below are for that commit.
**Roadmap ref:** P3-6.3a (gas/size), P3-6.3b (audit preparation, open findings), P3-4.2 (penalty tiers, S5), P3 onboarding (dincli)
**Previous plan:** [task-plan-021026-1](task-plan-021026-1.md) → [task_021026_19](../../tasks/task_021026_19.md) (all six Parts landed; [Discussion #216](https://github.com/InfiniteZeroFoundation/DevNet/discussions/216))

**Flow:**
1. umeradl reviews this plan on its PR.
2. I apply the review amendments here.
3. Once it is approved, the plan is forwarded as **one** `Developer/tasks/task_DDMMYY_n.md` spec with one Part per TP, and this file is marked as forwarded.

---

## Selection

After task_021026_19, the open issues that need no outside owner are either one decision away from code (#180, #193), or are what's left of an issue that has already partly landed (#201 Part A item 4).

While writing the [DevNet 2.0 wiki](https://github.com/InfiniteZeroFoundation/DevNet/wiki) for #207, I found that the DevNet 2.0 contracts can't yet be **operated** through dincli. These gaps have backlog rows (BL-27, BL-28) but no GitHub issue. I've included them because they block model-owner onboarding on DevNet 2.0 more directly than anything else open.

| # | Issue | Area | Why now |
|---|---|---|---|
| TP-1 | [#201](https://github.com/InfiniteZeroFoundation/DevNet/issues/201) Part A, item 4 | `DINTaskAuditor` size review | Left open in the [#201 status update](https://github.com/InfiniteZeroFoundation/DevNet/issues/201). `DINTaskAuditor` is at 22,718 B (1,858 B margin), so the gate warns on every PR, and TP-2 and later mechanism work add more bytes |
| TP-2 | [#180](https://github.com/InfiniteZeroFoundation/DevNet/issues/180) | Dual-role registration (auditor + aggregator, same GI) | The decision is all that's missing. Prototype: guard +103 B. Also carries the amendment-4 NatSpec fix |
| TP-3 | [#193](https://github.com/InfiniteZeroFoundation/DevNet/issues/193) | S5 recidivism per slasher contract | `DinValidatorStake` has about 14 KB headroom. Needs an option choice ([Decision 3](#decisions-requested)). The fix fits the existing storage gap |
| TP-4 | BL-27, BL-28 (issue to open on approval) | `dincli model-owner deploy` constructor args, `setDinToken`, `releaseGIRegistrationSlots` | Model owners can't deploy DevNet 2.0 task contracts from dincli today. The CLI harness only passes because it deploys the **hardhat** contracts |
| TP-5 | — (issue to open on approval) | dincli commands for rewards, encryption key, disputes | `startGI` reverts without `depositRewards`, and assigning test data reverts without auditor keys. dincli covers neither (it even points at a nonexistent `dincli auditor register-encryption-key`) |
| TP-6 | — (issue to open on approval) | Public docs drift | Found while writing the wiki. Stale command names and contract set in `Documentation/public/` |

---

## Status check at `740a613`

| Item | State at `740a613` |
|---|---|
| #201 A4 | `DINTaskAuditor` is 22,718 B runtime (1,858 B margin, gate **warns**). It has 16 public mappings, and several duplicate an existing view or have no reader outside the contract (see TP-1) |
| #180 | `registerDINAuditor` (`DINTaskAuditor.sol:667-698`) and `registerDINaggregator` (`DINTaskCoordinator.sol:401-434`) have no cross-role check. The PR #182 review ruled dual-role **not** intended (`adversarial-threat-model.md` Judgment call 2, Row 6 = KNOWN GAP). The stale "(not yet enforced)" NatSpec is still at `DinValidatorStake.sol:451` and `:462` |
| #193 | The S5 ring is `_partialSlashGIs[validator][msg.sender]` (`DinValidatorStake.sol:146`, used in `slashPartial` at `:294-322`), so it is counted per slasher **contract**. Even within one model, S1 (auditor contract) and S2 (coordinator) are separate rings. `MECHANISM_DESIGN.md:81` defines S5 per validator across both roles |
| BL-27 | `deploy.py:35` calls `constructor(stake)` and `:77` calls `constructor(stake, coordinator)`, but both contracts take a trailing `modelId_` (`DINTaskCoordinator.sol:290`, `DINTaskAuditor.sol:406`). Neither calls `setDinToken`. `modelId` is `immutable` and is only used for the per-model stake floor. The registry assigns `models.length` at **approval** (`DINModelRegistry.sol:237`) and doesn't check that it matches the contracts' `modelId()` |
| BL-28 | `releaseGIRegistrationSlots(uint)` (`DINTaskCoordinator.sol:1287`, `onlyOwner`, covers both contracts) has no dincli caller |
| Rewards / keys / disputes | dincli calls none of the following: `depositRewards` (`DINTaskAuditor.sol:481`), `claimReward`/`claimRewards` (`:583`/`:640`), `DinValidatorStake.registerEncryptionKey` (`:501`), the four test-data dispute functions (`:1480`, `:1524`, `:1557`, `:1601`), the coordinator dispute functions (`:1368`, `:1535`, `:1609`, `:1671`, `:1584`) |
| Docs | `din-workflow.md:7-12,21,63` (4 contracts, `withdraw`); `setup.md:34-42` (install from `main`); `roles/clients.md:34-67` (`train-lms --submit`); `roles/auditors.md:86-103` (no `reveal`); `roles/model-owner.md:87,104,116,134,146,252-261` (`registry …`, `create-genesis`, no `start-reveal`); `model-workflow.md:178,186,198,204,303,353-378` (the same); `ROADMAP.md:19` (still says 24,585 B / 9 B over) |

---

## Sequencing

| Item | Touches | Conflicts with | Rule |
|---|---|---|---|
| TP-1 | `DINTaskAuditor.sol` (getter visibility), the foundry tests that read those getters, `dincli/abis/DINTaskAuditor.json`, `DINTaskAuditor.md` §3 | TP-2 (same contract, size), TP-5 (views TP-5 reads) | **First.** Measure on the actual implementation and agree the getter set ([Decision 1](#decisions-requested)) |
| TP-2 | `DINTaskAuditor.registerDINAuditor`, `IDINTaskCoordinator` (`DINShared.sol`), a new error, `DinValidatorStake.sol` NatSpec, tests, threat model Row 6 | TP-1 | After TP-1, or as commit 2 of TP-1's PR (the same pattern as task_021026_19 A+B) |
| TP-3 | `DinValidatorStake.sol` (S5 storage + `slashPartial`), S5 tests, `DinValidatorStake.md`, threat model Row 11, deploy-script S5 keys | — | **In parallel with TP-1.** Different contract |
| TP-4 | `dincli/cli/modelownerd/deploy.py`, new `dincli model-owner gi release-slots`, dinrep approve check, `tests/dincli/` harness → foundry artifacts | TP-5 (same CLI area) | **In parallel with TP-1/TP-3.** dincli only |
| TP-5 | New dincli commands (`model-owner rewards …`, `rewards claim`, `auditor register-encryption-key`, dispute commands), `dincli/abis/DinEmission.json`, context helper, tests, role docs | TP-1 (getter set), TP-4 | After TP-1 merges (it reads `giRewardSnapshot`/`testDataDisputes`/`rewardClaimed`) |
| TP-6 | `Documentation/public/**`, `ROADMAP.md:19` | TP-4/TP-5 (new commands to document) | Last. Covers the new commands too |

One PR per TP, or TP-1 + TP-2 as two commits in one PR. Rebase on `develop` after each merge, with no stacked branches. PR #31/#32 (`dincli/sdk`, daemon) rebase onto these changes.

---

# TP-1 — #201 Part A item 4: `DINTaskAuditor` size review

Same approach as task_021026_19 Part A. Shrink the contract in place, with no library, split or deploy change. Only **getter visibility** changes. No state-changing function, event or storage slot changes.

**Prototype on `740a613`.** `via_ir`, 200 runs. Each line makes one public mapping `internal`; the last two lines combine several.

| Getter | Readers outside the contract | Saving | Note |
|---|---|---|---|
| `auditBatches` (struct array) | 1 foundry test | −100 B | `getAuditorsBatch` already returns the batch |
| `dinAuditors` | none | −83 B | `getDINtaskAuditors` already returns the list |
| `Is_testdataCIDs_Assigned` | none | −58 B | Unused |
| `auditorGIWeight` | none | −79 B | |
| `rewardClaimed` | none | −84 B | TP-5's claim command would read it, so **keep** |
| `testDataDisputes` | 2 foundry tests | −117 B | TP-5's dispute commands read it, so **keep** |
| `giRewardSnapshot` | 2 foundry tests | −145 B | TP-5 reads `settled`, so **keep** |
| **Recommended four** (the first four rows) | | **−320 B → 22,398 B** (2,178 B margin) | Clears the warn band. With TP-2: about 22,501 B |
| All seven | | −666 B → 22,052 B | Only if TP-5 reads that state some other way |

Scope:
- Make the agreed getters `internal`. Switch the one foundry test from `auditBatches` to `getAuditorsBatch`.
- Regenerate `dincli/abis/DINTaskAuditor.json` (`dump-abi --official`) and update `DINTaskAuditor.md` §3.
- Check the subgraph branch for reads of the dropped getters, and post an ABI note on PR #29 (as in task_021026_19 Part A).
- Do the "same review" of per-phase duplication that #201 item 4 asks for. Measure folding the near-duplicate dispute and reassignment paths. Commit a fold only if it actually shrinks the contract: in task_021026_19, `via_ir` made the coordinator folds **grow** it.

**Deliverables:** a size table from one build of the implementation. `forge test` (full suite, including `UpgradeValidation.t.sol`) and `pytest -m "not integration"` are green, and the gate is green.

**Estimate:** 1 day.

---

# TP-2 — #180: one address can't hold both roles in a GI

**Recommendation: a per-address cross-role guard** ([Decision 2](#decisions-requested)). The guard is Sybil-bypassable (a second address with its own stake), which the threat model already notes. But it forces the attacker to put up a second stake and makes the attack visible on-chain, for +103 B. Documenting stake cost as the only defence would also need a non-zero `maxConcurrentRegistrationsPerStakeUnit` default. That is a tokenomics call belonging to #155, so I'd rather not tie this fix to it.

- **Where the guard goes.** Aggregator registration (states 6–7) always comes **before** auditor registration (8–9) (`DINShared.sol:17-20`). So the guard belongs in `registerDINAuditor`: `if (dintaskcoordinatorContract.isDINAggregator(_GI, msg.sender)) revert TA_DualRoleNotAllowed();`. It needs `isDINAggregator(uint256,address)` added to `IDINTaskCoordinator`, and the coordinator's public mapping `isDINAggregator` (`DINTaskCoordinator.sol:34`) already provides it. A coordinator-side guard would never fire, because no auditor exists yet when aggregators register.
- **Prototype cost:** `DINTaskAuditor` goes from 22,718 to 22,821 B (+103 B). The coordinator is unchanged.
- **NatSpec (amendment 4):** fix `DinValidatorStake.sol:451` and `:462` ("not yet enforced"), and the "decremented at endGI time" note at `:121` (the decrement happens in `releaseGIRegistrationSlots`).
- **Tests** (next to the `StakingEnforcement.t.sol` registration tests):
  - An aggregator registering as an auditor in the same GI reverts.
  - Registering as an auditor in a different GI succeeds.
  - A different address with its own stake succeeds, which documents the Sybil limit.
- **Docs:** threat model Row 6 changes from KNOWN GAP to DEFENDED (with the Sybil-limit note), and its stale line refs are fixed. Update `DINTaskAuditor.md` (registration checks, §13 caveat) and the `DINShared.md` error row.

**Estimate:** 0.5 day.

---

# TP-3 — #193: S5 escalation across models

**Recommendation: a two-level check where the global level is time-based** ([Decision 3](#decisions-requested), options A/B/C below).

- **The per-slasher ring stays as it is** (per-model escalation, existing tests and semantics).
- **Add a per-validator global ring of `block.timestamp` values**, `_partialSlashTimes[validator]`, with `s5GlobalWindow` (seconds) and `s5GlobalThreshold`.
  - Timestamps are monotonic across every slasher, so the ascending-order trim that forced per-contract keying (`DinValidatorStake.sol:136-146`) stays safe.
  - `slashPartial` escalates when **either** level reaches its threshold, and clears both rings on escalation.
- **Also closes the same-model split.** S1 (auditor contract) and S2 (coordinator) misses by one validator in one model now add up.

Options for the decision:
- **A (recommended): two-level, as above.** Per-model behaviour is unchanged. The cross-model gap closes. Two new owner-settable params.
- **B: replace the per-slasher ring with the global timestamp ring.** Simpler, but it changes S5 from "per N GIs" to "per T seconds" for every model, and models with different GI cadences then mean different things.
- **C: accept and document.** Calibrate the per-model threshold as the issue describes, and leave Row 11 as an accepted trust assumption.

Scope (option A):
- **Storage.** Append the new storage before `__gap` (`DinValidatorStake.sol:174`) and shrink the gap by the slots used. `DinValidatorStakeV2` inherits the change, and `UpgradeValidation.t.sol` plus the `DeployPlatform.t.sol` upgrade tests must stay green.
- **Setter.** `setS5GlobalParams(window, threshold)` with the same validation style as `setS5RecidivismParams` (`:583-594`).
  - **Defaults:** `s5GlobalWindow = 7 days` and `s5GlobalThreshold = 2 × s5RecidivismThreshold` (6). These are placeholders until #155.
  - Set them in `initialize`. For an upgraded proxy, use a `reinitializer` or treat 0 as off (decide in the PR). Add optional deploy-script env keys `S5_GLOBAL_*`, matching the existing `S5_*` keys.
- **Event.** `ValidatorEscalatedS5` gets a level flag, or a sibling event, so indexers can tell which level fired.
- **Tests:**
  - **Two slashers below the threshold.** Two task contracts each slash one validator (threshold−1) times within the window. The global level escalates.
  - **Window expiry** resets the count.
  - **Per-model behaviour unchanged.** The existing S5 tests and `test_crossModelGICollision_slashPartialDoesNotUnderflow` stay green.
- **Docs:** `DinValidatorStake.md`, `MECHANISM_DESIGN.md` S5 row, and threat model Row 11 (change it to DEFENDED). Also record the separate discrepancy found here: `MECHANISM_DESIGN.md:87` says S5 is "entire slashable stake + blacklist", while the code does `MIN_STAKE` + a 7-day jail. Note it; don't change it in this TP.

**Estimate:** 1.5 days.

---

# TP-4 — BL-27/BL-28: dincli can deploy and run DevNet 2.0 task contracts

**`model-owner deploy` passes `modelId`.**
- Add `--model-id` to both deploy commands. The default is `DINModelRegistry.totalModels()`, which is the ID the next approval assigns (`DINModelRegistry.sol:237`, 0-based). Print a warning that the guess only holds if no other request is approved first.
- `deploy task-auditor` reads `modelId()` from the coordinator and refuses a mismatch.
- Fix the latent `NameError` when the `stake` entry is missing (`deploy.py:27-28`, `:61-62`).

**Mismatch check at approval** ([Decision 4](#decisions-requested)). `dincli dinrep registry approve-registration-request` reads the request's coordinator and auditor `modelId()` and compares them with `totalModels()`. On a mismatch it refuses, and prints that the owner must redeploy (`modelId` is `immutable`). An `--force` flag overrides this. The alternative is a contract-side check in `DINModelRegistry.approveModel`; the registry is upgradeable, but that is a platform upgrade.

**`setDinToken` at deploy.** Both deploy commands call `setDinToken(DinToken)`. Without it, `depositRewards` (and so `startGI`) can't work on the auditor, and coordinator disputes can't take a bond.

**`dincli model-owner gi release-slots <model_id> --gi N`** calls `releaseGIRegistrationSlots`. It is listed in the `gi end` output as the next step.

**Harness.** `tests/dincli/test_02_task_contracts.py` deploys from the **foundry** artifacts (bundled `dincli/abis/`) instead of hardhat ones, so the harness catches this class of drift.

**Tests:**
- Unit tests with the existing `SimpleNamespace` / `build_and_send_tx` monkeypatch pattern (`tests/test_dinrep_add_slasher.py`).
- The deploy commands send the 2- and 3-argument constructors with the chosen `modelId`, and call `setDinToken`.
- The approval check refuses a mismatch.
- `release-slots` sends the right call.

**Docs:** `roles/model-owner.md`, `model-workflow.md` deploy section, `DINTaskCoordinator.md` §10 No. 10 / `DINTaskAuditor.md` §13 No. 8 (remove the "dincli lags" caveats), BL-27/BL-28 status.

**Estimate:** 1.5 days.

---

# TP-5 — dincli commands for rewards, encryption keys and disputes

Every new command reuses `build_and_send_tx` and the `get_deployed_din_task_*_contract(model_id)` lookups. Approve-then-act steps share a small `approve_din(ctx, spender, amount)` helper, taken from the existing inline pattern in `dintoken.stake_dintokens` (`dincli/cli/dintoken.py:71-128`).

| Command | Calls | Notes |
|---|---|---|
| `dincli model-owner rewards deposit <model_id> --gi N --amount <DIN>` | approve + `depositRewards` | Anyone can fund. `gi start` checks `giRewardPool(next GI) > 0` first and points here, instead of reverting with `TC_GIRewardPoolNotFunded` |
| `dincli model-owner rewards fund-emission <model_id> --gi N` | `DinEmission.fundGI` | Needs `DinEmission.json` in `dincli/abis/` and a `get_deployed_din_emission_contract` helper (`din_info` already has the `emission` key) |
| `dincli rewards claim <model_id> --gi N` (all roles) and `dincli rewards withdraw` | `claimReward(gi)`, `claimRewards()` | Reads `giRewardSnapshot.settled` and `rewardClaimed` first and prints clear messages |
| `dincli auditor register-encryption-key` | `DinValidatorStake.registerEncryptionKey(pubkey)` | Generates `auditor_x25519.key` if missing (chmod 600; the owner key at `auditor_batches.py:170-177` should get the same), and registers the 32-byte pubkey. This is the command the existing error message already names |
| `dincli auditor dispute-test-data <model_id> --batch B` | approve + `openTestDataDispute` | Batch auditors only, before settlement (#205 / `740a613`) |
| `dincli model-owner disputes resolve-test-data …` / `reassign-test-data …` / `dincli … disputes close-expired …` | `resolveTestDataDispute`, `reassignAuditTestDataset`, `closeExpiredDispute` | Reuses `create-testdataset`'s encryption path for the reassignment |
| `dincli aggregator dispute …`, `dincli model-owner disputes resolve-aggregation/settle-recomputation …`, `… expire`, `… claim-bond` | the five coordinator dispute functions | Covers S4 |

**Tests:** one pytest per command group with mocked contracts. They cover the call arguments, the approve-before-act order, and the pre-checks (unsettled GI, already claimed, missing key).

**Docs:** role guides (`clients.md`, `auditors.md`, `aggregators.md`, `model-owner.md`) and `model-workflow.md` (fund before `gi start`, register the key before the first GI, claim after `gi end`). Then update the wiki pages that currently say "no dincli command yet".

**Estimate:** 3 days. If the review wants it smaller, the dispute commands can be split out.

---

# TP-6 — Public docs drift

These are the `Documentation/public/` lines that no longer match `develop` (listed in [Status check](#status-check-at-740a613)):
- `din-workflow.md`: the contract set and `withdraw`, rewritten from `roles/dinrep.md`.
- `setup.md`: the install path.
- `roles/clients.md`: `train-lms`, then `submit-lm`.
- `roles/auditors.md`: add `reveal`.
- `roles/model-owner.md` and `model-workflow.md`:
  - `task model-owner register-request` / `update-manifest-request` / `show-registration-request`
  - `create-genesis-model` / `submit-genesis-model`
  - `start-reveal` for evaluation, T1 and T2
  - the commands TP-4/TP-5 add
- `ROADMAP.md:19`: the stale 24,585 B sentence. The DevNet 2.0 vs 3.0 naming is left for the reviewer.

`python3 .github/scripts/check_doc_links.py Documentation` and `… Developer` must be green.

**Estimate:** 0.5 day.

---

## Decisions requested

1. **TP-1 getter set.** The recommended four (`auditBatches`, `dinAuditors`, `Is_testdataCIDs_Assigned`, `auditorGIWeight`) save −320 B. The alternative is all seven (−666 B), with TP-5 then reading dispute, snapshot and claim state through new views (which cost bytes back) or events.
2. **#180.** The per-address guard in `registerDINAuditor` (recommended, +103 B), or document stake cost as the defence with a non-zero concurrency cap (which needs a #155 value).
3. **#193.** Option A (two-level, time-based global ring; recommended), B (global ring only) or C (accept and document). For A, confirm the placeholder defaults: `7 days` / threshold `6`.
4. **TP-4 modelId check.** A dincli-side check at approval (recommended; no contract change) or a contract-side check in `DINModelRegistry.approveModel` (a platform upgrade).
5. **Issues.** TP-4, TP-5 and TP-6 have no GitHub issue. Should I open one issue each (BL-27/BL-28 → TP-4; dincli DevNet 2.0 commands → TP-5; docs drift → TP-6) before forwarding?

---

## Deferred (not in this plan)

| Issue | Reason |
|---|---|
| [#201](https://github.com/InfiniteZeroFoundation/DevNet/issues/201) Part B | Mechanism decision (the slash reason for committed-but-unrevealed), tied to #155 / #38 |
| [#194](https://github.com/InfiniteZeroFoundation/DevNet/issues/194) | Needs a design note first (refund path, CID repair) |
| [#78](https://github.com/InfiniteZeroFoundation/DevNet/issues/78) | Two decisions open: where the network-fee floor is enforced, and which gas-price input to use |
| [#154](https://github.com/InfiniteZeroFoundation/DevNet/issues/154) Part 2 | Owned through [task_240926_17](../../tasks/task_240926_17.md) Part 2 (`P3Adversarial.t.sol`). TP-2/TP-3 change Row 6/11 outcomes, so its tests should be written against the result |
| [#181](https://github.com/InfiniteZeroFoundation/DevNet/issues/181), [#178](https://github.com/InfiniteZeroFoundation/DevNet/issues/178) | Mainnet-grade (decentralized adjudication, VRF) |
| [#185](https://github.com/InfiniteZeroFoundation/DevNet/issues/185), #166, #167 | Long-run / umbrella |
| #155, #157, #158, #174, #42, #43, #24, #21, #20, #23, #75 | Assigned to others, deferred, or non-code |
| [#39](https://github.com/InfiniteZeroFoundation/DevNet/issues/39) workstream 2, [#38](https://github.com/InfiniteZeroFoundation/DevNet/issues/38) | Mechanism redesign tracking, not a single change |
| BL-29, BL-30, BL-31 | Each needs a design decision (FeeRouter bucket consumers, GI abort, S6 scope) |
| BL-32, BL-33 | Ideas (preflight `doctor`, deployment drift check). These are good candidates for the next plan |
