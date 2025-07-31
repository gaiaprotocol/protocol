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
    // Custom Errors (gas‑efficient reverts)
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
    // Events
    // ------------------------------------------------------------------
    event ProtocolFeeRecipientUpdated(address indexed protocolFeeRecipient);
    event ProtocolFeeRateUpdated(uint256 rate);
    event HoldingVerifierUpdated(address indexed verifier);

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
        uint256 baseAmount,
        uint256 rewardRatio,
        uint256 nonce,
        bytes memory signature
    ) public returns (uint256) {
        if (signature.length == 0) return 0; // Opt‑out path, saves gas
        if (rewardRatio > 1 ether) revert RewardRatioTooHigh();
        if (nonces[msg.sender] != nonce) revert InvalidNonce();

        bytes32 hash = keccak256(
            abi.encodePacked(address(this), block.chainid, msg.sender, baseAmount, rewardRatio, nonce)
        );
        bytes32 ethSignedHash = hash.toEthSignedMessageHash();

        address signer = ethSignedHash.recover(signature);
        if (signer != holdingVerifier) revert InvalidVerifier();

        nonces[msg.sender]++;

        return (baseAmount * rewardRatio) / 1 ether;
    }
}
