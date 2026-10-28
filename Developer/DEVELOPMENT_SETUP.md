# Development Setup

This file is the minimal setup entrypoint for contributors working on DevNet.

**Prerequisite:** [Wallet Setup](../Documentation/public/guides/wallet-setup.md) — for development, use demo mode or `ETH_PRIVATE_KEY_<n>` in `.env`. Never commit real keys.

## Requirements

- Python **>= 3.12**
- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `anvil`) — the primary Solidity toolchain
- Node.js + npm — only needed inside `foundry/` (for `npm ci`, see below) and if you're also touching the secondary `hardhat/` toolchain

## Local Python Setup

```bash
git checkout develop
pip install -e .
```

If you are working on the ML or DP service code, make sure your environment also contains the training dependencies used by the current model services, including PyTorch and the test runner you intend to use.

Run the Python test suite:

```bash
pytest                                        # run all tests
pytest tests/test_dintoken.py -k test_name    # run a single test
```

## Foundry (Solidity) Setup

Install Foundry if you don't have it yet:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Then build and test the contracts:

```bash
cd foundry && npm ci && forge build && forge test
```

`npm ci` must run before `forge test` — `Upgrades.validateImplementation` shells
out over FFI to `npx @openzeppelin/upgrades-core`, and without
`foundry/node_modules` already populated from the committed lockfile, the
parallel test run can race fetching that package. See [CLAUDE.md](../CLAUDE.md)
for the full explanation and the Hardhat (secondary toolchain) commands.

## Testing Reference

Deeper, feature-specific testing guides live under
[Documentation/technical/testing/](../Documentation/technical/testing/), including
the general [dincli testing guide](../Documentation/technical/testing/dincli-testing-guide.md).

## Where To Start

- general contribution flow: [CONTRIBUTING.md](CONTRIBUTING.md)
- beginner and scoped issue list: [GOOD_FIRST_ISSUES.md](GOOD_FIRST_ISSUES.md)

