# Task Plan: P3 Size Blocker + Open Security/dincli Findings (#201 A, #206, #192, #202, #205, #207)

**ID:** task-plan-021026-1
**Author:** Umer Majeed (@umermjd11)
**Reviewer:** @umeradl
**Created:** 2026-10-02
**Status:** Draft — pending review
**Proposed dates:** Oct 2 – Oct 12, 2026
**Repo:** https://github.com/InfiniteZeroFoundation/DevNet
**Base branch:** `develop` — plan written against commit `6ccc28c` (2026-09-30). Line numbers below are for that commit.
**Roadmap ref:** P3-6.3a (gas/size), P3-6.3b (audit preparation, open findings), P3-4.3 (dispute resolution), P3-SCR (auditor commit-reveal)

**Flow:**
1. umeradl reviews this plan on its PR.
2. I apply the review amendments here.
3. Once approved, each item (or agreed group of items) becomes a `Developer/tasks/task_DDMMYY_n.md` spec, and this file is marked as forwarded.

---

## Selection

These are the open issues I can start **now**. Each one either has an agreed fix, or needs only a small decision that this review can make. None is blocked on an open PR or assigned to someone else.

| # | Issue | Area | Why now |
|---|---|---|---|
| TP-1 | [#201](https://github.com/InfiniteZeroFoundation/DevNet/issues/201) **Part A** | `DINTaskCoordinator` size + CI size gate | Hard blocker. Nothing on `develop` can deploy to a real chain ([#201 decision comment](https://github.com/InfiniteZeroFoundation/DevNet/issues/201#issuecomment-5908303202)) |
| TP-2 | [#206](https://github.com/InfiniteZeroFoundation/DevNet/issues/206) | `registerDINaggregator` missing `onlyCurrentGI` | One-line fix plus tests. Needs TP-1's bytes |
| TP-3 | [#192](https://github.com/InfiniteZeroFoundation/DevNet/issues/192) (Approved) | Auditor commit hash isn't sender-bound | Approved with amendments 1–6. PR #191/#197 conflicts are gone ([status comment](https://github.com/InfiniteZeroFoundation/DevNet/issues/192#issuecomment-5917136640)) |
| TP-4 | [#202](https://github.com/InfiniteZeroFoundation/DevNet/issues/202) | dincli auditor commit retry + `aggregate-t2` stale batch id | dincli-only. Part 1 risks a slash for honest auditors |
| TP-5 | [#205](https://github.com/InfiniteZeroFoundation/DevNet/issues/205) | Test-data dispute reward-pool drain | Security. `DINTaskAuditor` has headroom. Needs a design choice (see [Decisions](#decisions-needed-from-the-reviewer)) |
| TP-6 | [#207](https://github.com/InfiniteZeroFoundation/DevNet/issues/207) | Wiki DIN-Representative page | PR #204 has merged, so the repo-side source page is final |

---

## Status check at `6ccc28c`

None of the six is implemented on `develop`:

| Issue | State at `6ccc28c` |
|---|---|
| #201 A | `DINTaskCoordinator` is **24,585 B** runtime (−9 B under EIP-170), `DINTaskAuditor` is 22,567 B (+2,009 B), both measured from `foundry/out/*.json` `deployedBytecode`. `ci.yml` runs plain `forge build`/`forge test` (`:60-66`) with no size check. `foundry/anvil.sh:6` sets `--code-size-limit 4294967295` without saying why |
| #206 | `registerDINaggregator(uint _GI) public` (`DINTaskCoordinator.sol:397`) has no `onlyCurrentGI` (the modifier is at `:246`). The auditor side has it (`DINTaskAuditor.sol:660`) |
| #192 | `revealAuditScore` checks `keccak256(abi.encodePacked(score, vote, salt))` (`DINTaskAuditor.sol:1160`). NatSpec at `:244`, `:1091`. dincli uses `Web3.solidity_keccak` (`dincli/cli/auditor.py:534`) |
| #202 | `evaluate_lms` makes a fresh salt (`auditor.py:533`) and calls `_save_commit` unconditionally after the send (`:550`). `aggregate_t2` rebinds `bid` in the T1 loop (`aggregator.py:547`) after reading it from `getTier2Batch` (`:525`) |
| #205 | `openTestDataDispute` (`DINTaskAuditor.sol:1461`) and `resolveTestDataDispute` (`:1495`) have no caller check. `disputeBondAmount` is 0 at deploy (`:283`). `test_resolveDispute_upheld_returnsBondAndPenalises` (`EncryptedTestData.t.sol:319`) encodes the attack as intended behaviour |
| #207 | Wiki still describes `dincli dindao`, three proxies, `set-admin`, and `withdraw` |

---

## Sequencing

| Item | Touches | Conflicts with | Rule |
|---|---|---|---|
| TP-1 | `DINTaskCoordinator.sol` (getters, `slashAggregators`), `ci.yml`, `anvil.sh`, `CONTRIBUTING.md`, `dincli/cli/aggregator.py`, `dincli/cli/modelownerd/aggregation.py`, `dincli/abis/DINTaskCoordinator.json`, coordinator tests | TP-2 (same contract, size) | **First.** |
| TP-2 | `DINTaskCoordinator.registerDINaggregator` + test | TP-1 | After TP-1 merges, or folded into TP-1 (see Decisions). |
| TP-3 | `DINTaskAuditor.revealAuditScore` + NatSpec, `dincli/cli/auditor.py`, ~12 foundry test files that commit scores, `DINTaskAuditor.md`, `DINShared.md` | TP-4 (`auditor.py`), TP-5 (`DINTaskAuditor.sol`) | **In parallel with TP-1.** Different contract. |
| TP-4 | `dincli/cli/auditor.py` `evaluate_lms`, `dincli/cli/aggregator.py` `aggregate_t2`, new tests | TP-3 (hash helper), TP-1 (`aggregator.py` getter switch) | After TP-3 and TP-1. Part 2 alone could go earlier. |
| TP-5 | `DINTaskAuditor` test-data dispute functions, `EncryptedTestData.t.sol`, `DINTaskAuditor.md` §13 | TP-3 (same contract) | After TP-3 merges, rebased. |
| TP-6 | GitHub wiki only | — | Anytime. |

One PR per item (TP-6 is a wiki edit, not a PR). Each PR rebases on `develop` after the previous one merges, with no stacked branches.

Long-running drafts PR #31/#32 touch `DINTaskAuditor.sol` and `dincli/cli/auditor.py`. They rebase on these changes, not the other way round, as in the #192 approval review.

---

# TP-1 — #201 Part A: EIP-170 budget, CI gate, `DINTaskCoordinator` back under budget

## Approach: shrink inside the same contract (no new contract, library, or deploy step)

Prototyped against `6ccc28c` in a throwaway copy. All figures are runtime bytes, `via_ir`, `optimizer_runs = 200`:

| Lever | Saving | Use? |
|---|---|---|
| Fold `slashAggregators`' duplicated T1/T2 loops (`:1119-1195`) into one internal `_slashBatch(GI, batchId, aggregators, finalCID, minStake, s2Amount, bool t2)`. The `bytes32` reasons (`AGG_T1_NO_SUBMISSION` etc.), the events, and the S2/full-slash split stay the same | **−471 B** | ✅ |
| Make the 10 per-aggregator getters `internal` (`t1`/`t2` × `SubmissionCID`, `Submitted`, `Votes`, `CommitHash`, `Committed`). Add one view: `getAggregatorSubmission(GI, TierKind, batchId, aggregator) → (committed, commitHash, submitted, cid, votes)` | **−355 B** | ✅ |
| Make the `tier1Batches`/`tier2Batches` auto-getters `internal`. They duplicate `getTier1Batch`/`getTier2Batch`, which already exist | **−115 B** each | ✅ |
| **Combined** | **23,542 B, margin 1,034 B**. With TP-2: 23,551 B, margin 1,025 B | |
| Lower `optimizer_runs` to 100 / 50 / 1 | −20 / −38 / −76 B | ❌ Too small for the gas cost |
| Fold T1/T2 `commit…`/`reveal…`/`finalize…` into shared internals (#201's first candidate) | **+166 to +177 B** (`via_ir` inlines the shared bodies) | ❌ |
| External library or a second contract | Not needed | ❌ Adds linking/deploy steps for every model owner |

The trade-off is churn on **view** ABI only. No state-changing function, event, or storage slot changes:

- **dincli:** 6 call sites move to `getAggregatorSubmission`: `dincli/cli/aggregator.py:213,265,322,532` and `dincli/cli/modelownerd/aggregation.py:109,154`.
- **Foundry tests** that read the removed getters (`t1CommitHash`, `t1Submitted`, `tier1FinalizedAt`, …) switch to the new view.
- **The subgraph (`feat/din-indexer`) doesn't `eth_call` any of these getters**; it only mentions them in docs. I'll post a note on PR #29 anyway.

**The margin is thin.** About 1,025 B after TP-2 meets a 1,024 B budget with almost nothing to spare. If the reviewer wants more, these are the next candidates (not measured yet). I'll report their sizes in the PR:
- fold `tier1FinalizedAt`/`tier2FinalizedAt` into a view
- merge tier-duplicated custom errors (`TC_T1EmptyCommitHash`/`TC_T2EmptyCommitHash`, `…AlreadyCommitted`, `…NoCommitFound`, `…RevealHashMismatch`) where the tier is already implied by the function

## Scope

- **A1. Size reduction** as in the table above.
- **A2. CI gate.** Add a step after `forge build` in `.github/workflows/ci.yml`, with a small script in `.github/scripts/`. It:
  - reads every `foundry/out/<file>.sol/<Contract>.json` for contracts under `foundry/src`, directly (not the `forge build --sizes` table, which leaves `DINTaskAuditor` out)
  - prints a size/margin table
  - fails if any runtime size exceeds `24,576 − budget`
  - also checks initcode against EIP-3860's 49,152 B
- **A3. `foundry/anvil.sh`:** keep the override, but add a comment saying it hides EIP-170, and point to the CI gate.
- **A4. Record the budget** in `Developer/CONTRIBUTING.md`.
- **A5. Docs:** update the state-variable and view tables in `DINTaskCoordinator.md`, and regenerate `dincli/abis/DINTaskCoordinator.json`.

## Deliverables

- [ ] `DINTaskCoordinator` ≤ `24,576 − budget`. Before/after table in the PR
- [ ] CI gate in place, and proven to fail on a deliberately oversized build (shown in the PR)
- [ ] dincli call sites moved, with `pytest` green. Bundled ABI refreshed
- [ ] `forge test` green across the full suite, including `UpgradeValidation.t.sol`
- [ ] `anvil.sh` comment, `CONTRIBUTING.md` budget, `DINTaskCoordinator.md` updated

**Estimate:** 3 days.

---

# TP-2 — #206: `onlyCurrentGI` on `registerDINaggregator`

- Add `onlyCurrentGI(_GI)` to `registerDINaggregator` (`DINTaskCoordinator.sol:397`).
- Regression tests: `registerDINaggregator(GI + 1)` and `registerDINaggregator(GI - 1)` revert with `TC_WrongGI`, and the current-GI path still works.
- Cost: +9 B (measured on top of TP-1).
- Update `DINTaskCoordinator.md` §10 if it lists this as a caveat.

**Estimate:** 0.5 day.

---

# TP-3 — #192: sender-bound auditor commit hash

Implements the [approval review](https://github.com/InfiniteZeroFoundation/DevNet/issues/192#issuecomment-5878722560) amendments 1–6:

1. **Contract:** `revealAuditScore` checks `keccak256(abi.encode(score, vote, salt, msg.sender, gi, batchId, modelIndex))`. Update the NatSpec at `:244`, `:1091` (and the formula's other mentions). The function signatures don't change.
2. **dincli:** add a helper `_audit_commit_hash(score, vote, salt, sender, gi, batch_id, model_index)` in `dincli/cli/auditor.py`, modelled on `_agg_commit_hash` (`dincli/cli/aggregator.py:65`), using `eth_abi.encode` + `Web3.keccak`. Use it at `:534`. `reveal_lms` is unchanged.
3. **Tests:** put the formula in one shared foundry test helper. Change every test that reuses one `commitHash` across auditors to hash per auditor (the list is in amendment 3).
4. **Regression tests** in `AuditorCommitReveal.t.sol`:
   - a copied hash plus a copied reveal reverts with `TA_RevealHashMismatch`
   - a hash built for model X doesn't reveal for model Y, another batch, or another GI
   - the honest path still finalizes
5. **Docs:** `DINTaskAuditor.md`, `DINShared.md` (`TA_RevealHashMismatch`).
6. **Sizes:** `DINTaskAuditor` before/after (the TP-1 gate reports it once merged).

**Estimate:** 2 days (most of it is test churn).

---

# TP-4 — #202: dincli auditor commit retry + `aggregate-t2` batch id

- **Part 1 (`evaluate_lms`, `auditor.py:530-553`):**
  - Before evaluating an LM, read `hasCommittedLM(GI, batchId, account, modelIndex)` and skip it if already committed, leaving its cache untouched.
  - Write the commit cache **before** sending the tx.
  - Tests modelled on `tests/test_aggregator_commit_retry.py`: an already-committed LM leaves the cache byte-identical and sends no tx; on a failed send, the cache matches the sent commit.
- **Part 2 (`aggregate_t2`):**
  - Rename the inner T1 loop variables (`aggregator.py:547`) so `bid` stays the T2 id for the models path, worker job, and container name.
  - Switch `batch_id` checks to `is not None`.
  - Add a test that the job/container name carries the T2 id when `tier1BatchCount > 1`.

**Estimate:** 1 day.

---

# TP-5 — #205: test-data dispute drain

**Proposed design: #205 options 1 + 2.** This needs reviewer confirmation.

- **Only the model owner's reveal can resolve.**
  - `resolveTestDataDispute` becomes owner-only.
  - A reveal matching the commitment clears the dispute: the bond is forfeited, as today.
  - A non-matching reveal upholds it.
- **Silence loses.** If the owner doesn't reveal within `disputeWindowBlocks`, `closeExpiredDispute` (`:1540`) **upholds** the dispute (bond back, penalty, reassignment) instead of forfeiting the bond.
- **Only batch auditors can open.**
  - `openTestDataDispute` requires `isBatchAuditor(gi, batchId, msg.sender)`.
  - `disputeBondAmount` gets a non-zero default. The value is to be agreed; it's settable afterwards, as today.
- **Tests:**
  - a non-owner resolve reverts
  - an owner reveal with the true `K` clears the dispute
  - owner silence past the window upholds it
  - a non-batch-auditor open reverts
  - rewrite `test_resolveDispute_upheld_returnsBondAndPenalises` / `_blocksFurtherOpen` (`EncryptedTestData.t.sol:319,341`), which currently encode the attack
- **Docs:** remove the caveat in `DINTaskAuditor.md` §13 No. 1 and describe the new flow. Check for dincli commands that call these functions and update them if needed.

**Estimate:** 2 days.

---

# TP-6 — #207: wiki DIN-Representative page

- Rewrite the wiki page against `Documentation/public/roles/dinrep.md` as merged in PR #204, covering every row of the issue's table.
- Keep the wiki conventions: `blob/develop/...` links, no assignee names or week-level dates.
- Pushed to the wiki repo. Link the revision on #207.

**Estimate:** 0.5 day.

---

## Decisions needed from the reviewer

1. **#201 budget:** is ≥ 1,024 B runtime margin confirmed? TP-1 meets it with ~10 B to spare after TP-2. If you want more headroom now, say so and TP-1 takes the extra candidates listed above.
2. **TP-1 + TP-2:** one PR or two? Two keeps the size refactor reviewable on its own. One avoids a 9 B follow-up PR.
3. **#205 design:** are options 1 + 2 accepted? What default `disputeBondAmount` value?
4. **View ABI churn in TP-1:** is replacing 10 public getters with `getAggregatorSubmission` acceptable, given that dincli is the only off-chain caller?

---

## Deferred (not in this plan)

| Issue | Reason |
|---|---|
| [#201](https://github.com/InfiniteZeroFoundation/DevNet/issues/201) Part B | Mechanism decision (commit-but-no-reveal slash reason), tied to #155/#38 |
| [#193](https://github.com/InfiniteZeroFoundation/DevNet/issues/193) | Needs a choice between the options (global window / two-level / accept) |
| [#194](https://github.com/InfiniteZeroFoundation/DevNet/issues/194) | Needs a design note first (refund path, CID repair) |
| [#180](https://github.com/InfiniteZeroFoundation/DevNet/issues/180) | Open question: is dual-role registration intended? |
| [#181](https://github.com/InfiniteZeroFoundation/DevNet/issues/181), [#178](https://github.com/InfiniteZeroFoundation/DevNet/issues/178) | Mainnet-grade (decentralized adjudication, VRF) |
| [#154](https://github.com/InfiniteZeroFoundation/DevNet/issues/154) | Owned via [task_240926_17](../../tasks/task_240926_17.md) |
| #155, #42, #43, #174, #157, #158, #167 | Assigned to others, or non-code |
| BL-27, BL-28 ([BACK_LOG.md](../../BACK_LOG.md)) | Real dincli gaps, but no GitHub issue yet. I can open issues for the next plan if wanted |
