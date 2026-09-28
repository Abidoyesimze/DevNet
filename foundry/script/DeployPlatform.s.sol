// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {DinToken} from "../src/DinToken.sol";
import {DinCoordinator} from "../src/DinCoordinator.sol";
import {DinValidatorStake} from "../src/DinValidatorStake.sol";
import {DINModelRegistry} from "../src/DINModelRegistry.sol";
import {DinTreasury} from "../src/DinTreasury.sol";
import {DinFeeRouter} from "../src/DinFeeRouter.sol";
import {DinEmission} from "../src/DinEmission.sol";

/// @notice Deploys the seven DIN platform contracts behind Transparent Proxies,
///         wires them together, and writes foundry/deployments/localhost.json.
///
/// Tokenomics parameters are read from the environment via vm.envOr, defaulting
/// to today's in-code values so local deploys and existing tests are unchanged.
/// Override any of these keys in your .env.<network> file for testnet/mainnet.
///
/// Env keys (see .env.example for full descriptions):
///   DIN_PER_ETH                 — DIN minted per ETH (default: 1_000_000 * 1e18)
///   MINT_CAP                    — max total DIN minted, 0 = uncapped (default: 0)
///   EMISSION_PER_GI             — initial DIN per GI (default: 100e18)
///   EMISSION_DECAY_BPS          — retention fraction bps per epoch (default: 8000)
///   EMISSION_EPOCH_LENGTH       — GIs per epoch (default: 100)
///   EMISSION_MAX_EPOCHS         — total epochs before emission stops (default: 10)
///   MIN_STAKE                   — minimum validator stake in DIN-wei (default: 10e18)
///   S5_RECIDIVISM_WINDOW        — rolling GI window for S5 escalation (default: 5)
///   S5_RECIDIVISM_THRESHOLD     — slashes in window to trigger S5 jail (default: 3)
///   S5_JAIL_DURATION            — jail duration in seconds (default: 604800 = 7 days)
///   S6_NO_PARTICIPATION_THRESHOLD — no-participation events before S6 fires (default: 3)
///
/// Usage (from repo root):
///   ./foundry/anvil.sh &
///   forge clean
///   cd foundry && forge script script/DeployPlatform.s.sol \
///     --rpc-url http://127.0.0.1:8545 \
///     --broadcast \
///     --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
///     --unlocked
///
/// Then import into dincli:
///   dincli system import-deployments --foundry
contract DeployPlatform is Script {
    using stdJson for string;

    // ── Tokenomics defaults (match contract initialize values) ────────────────
    uint256 internal constant DEFAULT_DIN_PER_ETH        = 1_000_000 * 1e18;
    uint256 internal constant DEFAULT_MINT_CAP           = 0;
    uint256 internal constant DEFAULT_EMISSION_PER_GI    = 100e18;
    uint256 internal constant DEFAULT_EMISSION_DECAY_BPS = 8000;
    uint256 internal constant DEFAULT_EMISSION_EPOCH_LEN = 100;
    uint256 internal constant DEFAULT_EMISSION_MAX_EPOCHS= 10;
    uint256 internal constant DEFAULT_MIN_STAKE          = 10 * 1e18;
    uint256 internal constant DEFAULT_S5_WINDOW          = 5;
    uint256 internal constant DEFAULT_S5_THRESHOLD       = 3;
    uint256 internal constant DEFAULT_S5_JAIL_DURATION   = 7 days;
    uint256 internal constant DEFAULT_S6_THRESHOLD       = 3;

    function run() external {
        // ── Read overrides from environment ────────────────────────────────
        uint256 dinPerEth        = vm.envOr("DIN_PER_ETH",                  DEFAULT_DIN_PER_ETH);
        uint256 mintCap          = vm.envOr("MINT_CAP",                     DEFAULT_MINT_CAP);
        uint256 emissionPerGI    = vm.envOr("EMISSION_PER_GI",              DEFAULT_EMISSION_PER_GI);
        uint256 emissionDecayBps = vm.envOr("EMISSION_DECAY_BPS",           DEFAULT_EMISSION_DECAY_BPS);
        uint256 emissionEpochLen = vm.envOr("EMISSION_EPOCH_LENGTH",        DEFAULT_EMISSION_EPOCH_LEN);
        uint256 emissionMaxEpochs= vm.envOr("EMISSION_MAX_EPOCHS",          DEFAULT_EMISSION_MAX_EPOCHS);
        uint256 minStake         = vm.envOr("MIN_STAKE",                    DEFAULT_MIN_STAKE);
        uint256 s5Window         = vm.envOr("S5_RECIDIVISM_WINDOW",         DEFAULT_S5_WINDOW);
        uint256 s5Threshold      = vm.envOr("S5_RECIDIVISM_THRESHOLD",      DEFAULT_S5_THRESHOLD);
        uint256 s5JailDuration   = vm.envOr("S5_JAIL_DURATION",             DEFAULT_S5_JAIL_DURATION);
        uint256 s6Threshold      = vm.envOr("S6_NO_PARTICIPATION_THRESHOLD",DEFAULT_S6_THRESHOLD);

        if (dinPerEth == DEFAULT_DIN_PER_ETH)
            console.log("[INFO] DIN_PER_ETH not set - using default:", dinPerEth);
        if (mintCap == DEFAULT_MINT_CAP)
            console.log("[INFO] MINT_CAP not set - using default (uncapped)");
        if (minStake == DEFAULT_MIN_STAKE)
            console.log("[INFO] MIN_STAKE not set - using default:", minStake);

        vm.startBroadcast();

        // 1. DinTreasury — no dependencies
        address dinTreasuryProxy = Upgrades.deployTransparentProxy(
            "DinTreasury.sol:DinTreasury",
            msg.sender,
            abi.encodeCall(DinTreasury.initialize, ())
        );
        console.log("DinTreasury proxy:      ", dinTreasuryProxy);

        // 2. DinToken — no init args
        address dinTokenProxy = Upgrades.deployTransparentProxy(
            "DinToken.sol:DinToken",
            msg.sender,
            abi.encodeCall(DinToken.initialize, ())
        );
        console.log("DinToken proxy:         ", dinTokenProxy);

        // 3. DinFeeRouter — receives DinToken and DinTreasury proxies
        address dinFeeRouterProxy = Upgrades.deployTransparentProxy(
            "DinFeeRouter.sol:DinFeeRouter",
            msg.sender,
            abi.encodeCall(DinFeeRouter.initialize, (dinTokenProxy, dinTreasuryProxy))
        );
        console.log("DinFeeRouter proxy:     ", dinFeeRouterProxy);

        // 4. DinCoordinator — receives the DinToken proxy address
        address dinCoordinatorProxy = Upgrades.deployTransparentProxy(
            "DinCoordinator.sol:DinCoordinator",
            msg.sender,
            abi.encodeCall(DinCoordinator.initialize, (dinTokenProxy))
        );
        console.log("DinCoordinator proxy:   ", dinCoordinatorProxy);

        // 5. Wire DinToken → DinCoordinator (one-shot setter)
        DinToken(dinTokenProxy).setCoordinator(dinCoordinatorProxy);
        console.log("DinToken coordinator wired");

        // 6. Wire DinCoordinator → DinFeeRouter, and authorise it as a fee
        //    source so its sweepFeesToRouter() calls are accepted (onlyFeeSource).
        DinCoordinator(payable(dinCoordinatorProxy)).setFeeRouter(dinFeeRouterProxy);
        DinFeeRouter(dinFeeRouterProxy).addFeeSource(dinCoordinatorProxy);
        console.log("DinCoordinator feeRouter wired");

        // 7. DinValidatorStake — receives both token and coordinator proxies
        address dinValidatorStakeProxy = Upgrades.deployTransparentProxy(
            "DinValidatorStake.sol:DinValidatorStake",
            msg.sender,
            abi.encodeCall(
                DinValidatorStake.initialize,
                (dinTokenProxy, dinCoordinatorProxy)
            )
        );
        console.log("DinValidatorStake proxy:", dinValidatorStakeProxy);

        // 8. Wire DinCoordinator → DinValidatorStake
        DinCoordinator(payable(dinCoordinatorProxy))
            .updateValidatorStakeContract(dinValidatorStakeProxy);
        console.log("DinCoordinator stake contract wired");

        // 9. Wire DinValidatorStake → DinTreasury for slash distribution
        DinValidatorStake(dinValidatorStakeProxy).setSlashTreasury(dinTreasuryProxy);
        console.log("DinValidatorStake slashTreasury wired");

        // 10. DINModelRegistry — receives the stake proxy
        address dinModelRegistryProxy = Upgrades.deployTransparentProxy(
            "DINModelRegistry.sol:DINModelRegistry",
            msg.sender,
            abi.encodeCall(
                DINModelRegistry.initialize,
                (dinValidatorStakeProxy)
            )
        );
        console.log("DINModelRegistry proxy: ", dinModelRegistryProxy);

        // 11. Authorise DINModelRegistry as a fee source on DinFeeRouter, so its
        //     later sweepFeesToRouter() calls are accepted (onlyFeeSource).
        DinFeeRouter(dinFeeRouterProxy).addFeeSource(dinModelRegistryProxy);
        console.log("DINModelRegistry added as fee source");

        // 12. Wire DINModelRegistry → DinFeeRouter
        DINModelRegistry(dinModelRegistryProxy).setFeeRouter(dinFeeRouterProxy);
        console.log("DINModelRegistry feeRouter wired");

        // 13. DinEmission — schedule from env overrides (defaults: 100 DIN/GI,
        //     8000 bps retention per epoch, 100 GIs/epoch, 10 epochs).
        address dinEmissionProxy = Upgrades.deployTransparentProxy(
            "DinEmission.sol:DinEmission",
            msg.sender,
            abi.encodeCall(
                DinEmission.initialize,
                (
                    dinCoordinatorProxy,
                    dinTokenProxy,
                    emissionPerGI,
                    emissionDecayBps,
                    emissionEpochLen,
                    emissionMaxEpochs
                )
            )
        );
        console.log("DinEmission proxy:      ", dinEmissionProxy);

        // 14. Wire DinCoordinator → DinEmission
        DinCoordinator(payable(dinCoordinatorProxy)).setEmissionContract(dinEmissionProxy);
        console.log("DinCoordinator emission contract wired");

        // 15. Apply post-deploy tokenomics overrides when they differ from defaults.
        if (dinPerEth != DEFAULT_DIN_PER_ETH) {
            DinCoordinator(payable(dinCoordinatorProxy)).updateDinPerEth(dinPerEth);
            console.log("DinCoordinator.dinPerEth set to:", dinPerEth);
        }
        if (mintCap != DEFAULT_MINT_CAP) {
            DinCoordinator(payable(dinCoordinatorProxy)).setMintCap(mintCap);
            console.log("DinCoordinator.mintCap set to:", mintCap);
        }
        if (minStake != DEFAULT_MIN_STAKE) {
            DinValidatorStake(dinValidatorStakeProxy).setMinStake(minStake);
            console.log("DinValidatorStake.minStake set to:", minStake);
        }
        if (
            s5Window     != DEFAULT_S5_WINDOW     ||
            s5Threshold  != DEFAULT_S5_THRESHOLD  ||
            s5JailDuration != DEFAULT_S5_JAIL_DURATION
        ) {
            DinValidatorStake(dinValidatorStakeProxy).setS5RecidivismParams(
                s5Window, s5Threshold, s5JailDuration
            );
            console.log("DinValidatorStake S5 params updated");
        }
        if (s6Threshold != DEFAULT_S6_THRESHOLD) {
            DinValidatorStake(dinValidatorStakeProxy).setS6NoParticipationThreshold(s6Threshold);
            console.log("DinValidatorStake.s6NoParticipationThreshold set to:", s6Threshold);
        }

        console.log("--- Effective tokenomics ---");
        console.log("dinPerEth:            ", dinPerEth);
        console.log("mintCap:              ", mintCap);
        console.log("emissionPerGI:        ", emissionPerGI);
        console.log("emissionDecayBps:     ", emissionDecayBps);
        console.log("emissionEpochLength:  ", emissionEpochLen);
        console.log("emissionMaxEpochs:    ", emissionMaxEpochs);
        console.log("minStake:             ", minStake);
        console.log("s5Window:             ", s5Window);
        console.log("s5Threshold:          ", s5Threshold);
        console.log("s5JailDuration:       ", s5JailDuration);
        console.log("s6Threshold:          ", s6Threshold);

        // ProxyAdmin — OZ v5 deploys one ProxyAdmin per proxy; record all seven
        address proxyAdminTreasury    = Upgrades.getAdminAddress(dinTreasuryProxy);
        address proxyAdminToken       = Upgrades.getAdminAddress(dinTokenProxy);
        address proxyAdminCoordinator = Upgrades.getAdminAddress(dinCoordinatorProxy);
        address proxyAdminFeeRouter   = Upgrades.getAdminAddress(dinFeeRouterProxy);
        address proxyAdminStake       = Upgrades.getAdminAddress(dinValidatorStakeProxy);
        address proxyAdminRegistry    = Upgrades.getAdminAddress(dinModelRegistryProxy);
        address proxyAdminEmission    = Upgrades.getAdminAddress(dinEmissionProxy);
        console.log("ProxyAdmin (treasury):  ", proxyAdminTreasury);
        console.log("ProxyAdmin (token):     ", proxyAdminToken);
        console.log("ProxyAdmin (coord):     ", proxyAdminCoordinator);
        console.log("ProxyAdmin (feeRouter): ", proxyAdminFeeRouter);
        console.log("ProxyAdmin (stake):     ", proxyAdminStake);
        console.log("ProxyAdmin (registry):  ", proxyAdminRegistry);
        console.log("ProxyAdmin (emission):  ", proxyAdminEmission);

        vm.stopBroadcast();

        // 15. Write deployments JSON — same schema as hardhat/deployments/localhost.json
        _writeDeployments(
            dinTreasuryProxy,
            dinTokenProxy,
            dinCoordinatorProxy,
            dinFeeRouterProxy,
            dinValidatorStakeProxy,
            dinModelRegistryProxy,
            dinEmissionProxy,
            proxyAdminTreasury,
            proxyAdminToken,
            proxyAdminCoordinator,
            proxyAdminFeeRouter,
            proxyAdminStake,
            proxyAdminRegistry,
            proxyAdminEmission
        );
    }

    function _writeDeployments(
        address dinTreasury,
        address dinToken,
        address dinCoordinator,
        address dinFeeRouter,
        address dinValidatorStake,
        address dinModelRegistry,
        address dinEmission,
        address proxyAdminTreasury,
        address proxyAdminToken,
        address proxyAdminCoordinator,
        address proxyAdminFeeRouter,
        address proxyAdminStake,
        address proxyAdminRegistry,
        address proxyAdminEmission
    ) internal {
        string memory json = "deployments";
        vm.serializeAddress(json, "dinTreasury", dinTreasury);
        vm.serializeAddress(json, "dinToken", dinToken);
        vm.serializeAddress(json, "dinCoordinator", dinCoordinator);
        vm.serializeAddress(json, "dinFeeRouter", dinFeeRouter);
        vm.serializeAddress(json, "dinValidatorStake", dinValidatorStake);
        vm.serializeAddress(json, "dinModelRegistry", dinModelRegistry);
        vm.serializeAddress(json, "dinEmission", dinEmission);
        vm.serializeAddress(json, "proxyAdminTreasury", proxyAdminTreasury);
        vm.serializeAddress(json, "proxyAdminToken", proxyAdminToken);
        vm.serializeAddress(json, "proxyAdminCoordinator", proxyAdminCoordinator);
        vm.serializeAddress(json, "proxyAdminFeeRouter", proxyAdminFeeRouter);
        vm.serializeAddress(json, "proxyAdminStake", proxyAdminStake);
        vm.serializeAddress(json, "proxyAdminRegistry", proxyAdminRegistry);
        string memory finalJson = vm.serializeAddress(
            json,
            "proxyAdminEmission",
            proxyAdminEmission
        );

        string memory outDir = string.concat(vm.projectRoot(), "/deployments");
        vm.createDir(outDir, true);

        string memory outPath = string.concat(outDir, "/localhost.json");
        vm.writeJson(finalJson, outPath);
        console.log("Deployments written to:", outPath);
    }
}
