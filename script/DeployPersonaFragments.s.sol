// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {PersonaFragments} from "../src/social/PersonaFragments.sol";

/// @notice Deploys a UUPS proxy for PersonaFragments using a Ledger signer.
/// @dev Run with:
///      forge script script/DeployPersonaFragments.s.sol \
///        --rpc-url <RPC_URL> \
///        --ledger \
///        --sender <LEDGER_ADDRESS> \
///        --broadcast \
///        --ffi \
///        --verify
contract DeployPersonaFragmentsScript is Script {
    // -------------------------------------------------------------------------
    // Deployment configuration
    // -------------------------------------------------------------------------

    /// @notice Address that receives the protocol fee.
    address payable internal constant PROTOCOL_FEE_RECIPIENT = payable(0x48674148a4043EAadB92E5D8D7C493121D6489b1);

    /// @notice Protocol fee rate (1 ether = 100%, so 0.025 ether = 2.5%).
    uint256 internal constant PROTOCOL_FEE_RATE = 0.025 ether;

    /// @notice Persona owner fee rate (1 ether = 100%, so 0.025 ether = 2.5%).
    uint256 internal constant PERSONA_OWNER_FEE_RATE = 0.025 ether;

    /// @notice Linear price increment per fragment (in wei).
    ///         1e15 wei = 0.001 ether.
    uint256 internal constant PRICE_INCREMENT_PER_FRAGMENT = 1e15;

    /// @notice Off-chain signer that verifies holding rewards.
    address internal constant HOLDING_VERIFIER = 0x22C51C670338459a7bcbe0E0228C3694B3702104;

    /// @notice Artifact name used by OpenZeppelin upgrades tooling.
    string internal constant ARTIFACT = "PersonaFragments.sol";

    // -------------------------------------------------------------------------
    // Entry point
    // -------------------------------------------------------------------------

    function run() external returns (address proxy) {
        /**
         * 1) Start broadcasting.
         *
         * The actual sender is provided by Forge via CLI flags:
         *   --ledger --sender <LEDGER_ADDRESS>
         *
         * This script intentionally does not read PRIVATE_KEY or addresses
         * from env to keep Ledger flow explicit and simple.
         */
        vm.startBroadcast();

        /**
         * 2) Deploy UUPS proxy + implementation, and call initialize().
         *
         *    Upgrades.deployUUPSProxy will:
         *      - deploy the implementation contract
         *      - deploy the UUPS proxy pointing to it
         *      - execute the initializer with the encoded arguments
         */
        proxy = Upgrades.deployUUPSProxy(
            ARTIFACT,
            abi.encodeCall(
                PersonaFragments.initialize,
                (
                    PROTOCOL_FEE_RECIPIENT,
                    PROTOCOL_FEE_RATE,
                    PERSONA_OWNER_FEE_RATE,
                    PRICE_INCREMENT_PER_FRAGMENT,
                    HOLDING_VERIFIER
                )
            )
        );

        vm.stopBroadcast();

        /**
         * 3) Log the deployed proxy address.
         */
        console.log("PersonaFragments UUPS proxy deployed via Ledger at:", proxy);
    }
}
