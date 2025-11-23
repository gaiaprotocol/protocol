// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

abstract contract HoldingRewardsBase is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ------------------------------------------------------------------
    // Custom Errors (gas-efficient reverts)
    // ------------------------------------------------------------------
    error InvalidProtocolFeeRecipient();
    error FeeRateExceedsMaximum();
    error InvalidVerifierAddress();
    error RewardRatioTooHigh();
    error InvalidNonce();
    error InvalidVerifier();

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------
    address payable public protocolFeeRecipient;
    uint256 public protocolFeeRate; // 1 ether == 100%
    address public holdingVerifier;
    mapping(address => uint256) public nonces;

    // ------------------------------------------------------------------
    // Storage Gap (Critical for Upgradeability)
    // ------------------------------------------------------------------
    // Reserved space to prevent storage collision during future upgrades
    uint256[50] private __gap;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event ProtocolFeeRecipientUpdated(address indexed protocolFeeRecipient);
    event ProtocolFeeRateUpdated(uint256 rate);
    event HoldingVerifierUpdated(address indexed verifier);

    // ------------------------------------------------------------------
    // Initializer
    // ------------------------------------------------------------------
    function __HoldingRewardsBase_init(
        address payable _protocolFeeRecipient,
        uint256 _protocolFeeRate,
        address _holdingVerifier
    ) internal onlyInitializing {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        if (_protocolFeeRecipient == address(0)) revert InvalidProtocolFeeRecipient();
        if (_holdingVerifier == address(0)) revert InvalidVerifierAddress();
        if (_protocolFeeRate > 1 ether) revert FeeRateExceedsMaximum();

        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeRate = _protocolFeeRate;
        holdingVerifier = _holdingVerifier;

        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
        emit ProtocolFeeRateUpdated(_protocolFeeRate);
        emit HoldingVerifierUpdated(_holdingVerifier);
    }

    // ------------------------------------------------------------------
    // Admin setters
    // ------------------------------------------------------------------
    function updateProtocolFeeRecipient(address payable _protocolFeeRecipient) external onlyOwner {
        if (_protocolFeeRecipient == address(0)) revert InvalidProtocolFeeRecipient();
        protocolFeeRecipient = _protocolFeeRecipient;
        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
    }

    function updateProtocolFeeRate(uint256 _rate) external onlyOwner {
        if (_rate > 1 ether) revert FeeRateExceedsMaximum();
        protocolFeeRate = _rate;
        emit ProtocolFeeRateUpdated(_rate);
    }

    function updateHoldingVerifier(address _verifier) external onlyOwner {
        if (_verifier == address(0)) revert InvalidVerifierAddress();
        holdingVerifier = _verifier;
        emit HoldingVerifierUpdated(_verifier);
    }

    // ------------------------------------------------------------------
    // Reward calculation
    // ------------------------------------------------------------------
    function calculateHoldingReward(
        uint256 baseAmount, // The actual calculated protocol fee amount
        uint256 rewardRatio, // The ratio of the fee returned to the user (1 ether = 100%)
        uint256 nonce,
        bytes memory signature
    ) public returns (uint256) {
        // 1. Skip logic if signature is empty (Gas optimization)
        if (signature.length == 0) return 0;

        // 2. Validate ratio
        if (rewardRatio > 1 ether) revert RewardRatioTooHigh();

        // 3. Validate Nonce (Prevent replay attacks)
        if (nonces[msg.sender] != nonce) revert InvalidNonce();

        // 4. Verify Signature (CRITICAL FIX)
        // 'baseAmount' (variable fee) is EXCLUDED from the hash.
        // Including 'baseAmount' causes transaction failures when the price (and thus the fee)
        // changes between signature generation and transaction execution (slippage).
        // Verifying 'rewardRatio' is sufficient to prevent manipulation.
        bytes32 hash = keccak256(abi.encodePacked(address(this), block.chainid, msg.sender, rewardRatio, nonce));
        bytes32 ethSignedHash = hash.toEthSignedMessageHash();

        address signer = ethSignedHash.recover(signature);
        if (signer != holdingVerifier) revert InvalidVerifier();

        // 5. Increment Nonce
        nonces[msg.sender]++;

        // 6. Calculate and return actual reward
        return (baseAmount * rewardRatio) / 1 ether;
    }
}
