# DIN-Representative Documentation

The DIN-Representative administers the core infrastructure contracts of the DIN network (a DIN-DAO is planned to take over this role after mainnet). This includes deploying the fundamental contracts and authorizing participants (slashers) who can penalize misbehaving validators.

---

## 1. Deployment

Deploy the core contracts in the order listed below. Each contract depends on the previous one being live.

> [!NOTE]
> The `--artifact` flag must point to the compiled JSON output from Hardhat/ Foundry (contains the ABI and bytecode).

### 1. DIN Coordinator

The main coordinator contract that governs network-wide operations.

```bash
dincli dinrep deploy din-coordinator --artifact <path_to_artifact>
```

### 2. Validator Stake

The staking contract used by validators (Auditors, Aggregators).

```bash
dincli dinrep deploy din-validator-stake --artifact <path_to_artifact>
```

### 3. Model Registry

Records federated learning tasks, assigns a unique `model_id` to each task, and stores the initial global model reference and manifest for a task.

```bash
dincli dinrep deploy din-model-registry --artifact <path_to_artifact>
```

---

## 2. Registry Management

### View Total Models

Check how many models are currently approved in the network.

```bash
dincli dinrep registry total-models
```

---

### Model Registration Approval

Model registration follows a **request → approval** flow. Model Owners submit requests; the DIN-Representative reviews and approves or rejects them.

**List pending registration requests:**

```bash
dincli dinrep registry list-pending-requests [--type model|manifest]
```

**Approve a model registration request:**

```bash
dincli dinrep registry approve-registration-request <requestId>
```

> [!IMPORTANT]
> Approval revalidates the coordinator and auditor contracts at the time of the call. If either contract has lost slasher status or been transferred to a different owner since the request was submitted, the transaction will revert. The requester must submit a new request.

**Reject a model registration request:**

```bash
dincli dinrep registry reject-registration-request <requestId>
```

The registration fee is retained by the contract in both cases.

---

### Manifest Update Approval

Manifest updates also follow a request → approval flow.

**Approve a manifest update:**

```bash
dincli dinrep registry approve-manifest-update <requestId>
```

> [!NOTE]
> Approving a manifest update for a disabled model will revert. Enable the model first if the update is intentional.

**Reject a manifest update:**

```bash
dincli dinrep registry reject-manifest-update <requestId>
```

---

### Kill Switch — Disable / Enable Models

Disable a model immediately. This blocks manifest update requests from the model owner and should be checked by downstream contracts (`TaskCoordinator`, `TaskAuditor`) before executing any model tasks.

```bash
# Disable a model (emergency stop)
dincli dinrep registry disable-model <modelId>

# Re-enable a model
dincli dinrep registry enable-model <modelId>
```

> [!CAUTION]
> Disabling a model does not delete it. All on-chain history is preserved. Downstream contracts must actively check `modelDisabled(modelId)` for the kill switch to have operational effect.

---

## 3. Fee Governance

The registry charges fees for model registration and manifest update requests. All four fee parameters are controlled by the DIN-Representative.

| Parameter | Default | Applies To |
|-----------|---------|-----------|
| `openSourceFee` | 0.000001 ETH | Open-source model registration |
| `proprietaryFee` | 0.00001 ETH | Proprietary model registration |
| `openSourceUpdateFee` | 0.0000001 ETH | Open-source manifest update requests |
| `proprietaryUpdateFee` | 0.000001 ETH | Proprietary manifest update requests |

**Update a single fee:**

```bash
dincli dinrep registry set-open-source-fee <eth>
dincli dinrep registry set-proprietary-fee <eth>
dincli dinrep registry set-open-source-update-fee <eth>
dincli dinrep registry set-proprietary-update-fee <eth>
```

**Update all fees atomically (preferred for governance proposals):**

```bash
dincli dinrep registry set-fees \
  --open-source <eth> \
  --proprietary <eth> \
  --open-source-update <eth> \
  --proprietary-update <eth>
```

### Sweep Accumulated Fees

Collected ETH stays in the contract that received it until the DIN-Representative sweeps it to `DinFeeRouter`. There are two sweep commands:

```bash
# Model registration and manifest update fees held by DINModelRegistry
dincli dinrep registry sweep-fees

# ETH that DinCoordinator received from DIN purchases (depositAndMint)
dincli dinrep coordinator sweep-fees
```

- **Owner only:** the active wallet must be the contract's owner, i.e. the DIN-Representative wallet.
- **Router wiring:** `foundry/script/DeployPlatform.s.sol` connects both contracts to the fee router when it deploys them. The CLI has no command for changing the router.
- **Preview and confirmation:** each command reads the router's current `ethSplit`, shows how much will go to each bucket, and asks before sending. Pass `--yes` to skip the prompt.
- **One sweep moves the whole balance.**

> [!WARNING]
> **Only the Treasury share leaves the router.** With the default `ethSplit` (validator pool 95%, Treasury 5%), the Treasury receives 5% of each sweep. The validator-pool, storage and public-goods shares stay in `DinFeeRouter` as `accruedEth`, and nothing can withdraw them yet: that waits on the future P3-5.2 / RES-1 consumers. A sweep can't be reversed, so treat swept non-Treasury ETH as locked until those consumers ship.

---

## 4. Slasher Management

Slashers are contracts authorized to penalize misbehaving participants. The Task Coordinator and Task Auditor contracts must be registered as slashers before they can enforce penalties.

### Register Task Coordinator as a Slasher

> **Prerequisite** — the following key must be set in your `.env` file:
> - `<NETWORK>_DINTaskCoordinator_Contract_Address`  
>   *(e.g. `SEPOLIA_OP_DEVNET_DINTaskCoordinator_Contract_Address`)*

```bash
dincli dinrep add-slasher --taskCoordinator
```

### Register Task Auditor as a Slasher

> **Prerequisite** — the following keys must be set in your `.env` file:
> - `<NETWORK>_DINTaskCoordinator_Contract_Address`  
>   *(e.g. `SEPOLIA_OP_DEVNET_DINTaskCoordinator_Contract_Address`)*
> - `<NETWORK>_<TASK_COORDINATOR_ADDRESS>_DINTaskAuditor_Contract_Address`  
>   *(e.g. `SEPOLIA_OP_DEVNET_0x1234...7890_DINTaskAuditor_Contract_Address`)*

```bash
dincli dinrep add-slasher --taskAuditor
```

### Register by Address Directly

If you already know the contract address, you can pass it explicitly instead of relying on the `.env` file:

```bash
dincli dinrep add-slasher --contract <contract_address>
```

---

## Workflow

1. **Deploy** — Coordinator → Validator Stake → Model Registry (in order).
2. **Configure Slashers** — After each new task is created, register its Task Coordinator and Task Auditor as slashers.
3. **Process Registration Requests** — Review pending `ModelRequest` entries; approve or reject each one.
4. **Process Manifest Update Requests** — Review pending `ManifestUpdateRequest` entries.
5. **Monitor** — Use registry commands to track network growth and model status.
6. **Emergency** — Use `disable-model` if a model needs to be stopped immediately.

