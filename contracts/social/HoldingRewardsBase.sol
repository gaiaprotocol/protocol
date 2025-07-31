// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

abstract contract HoldingRewardsBase is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    address payable public protocolFeeRecipient;
    uint256 public protocolFeeRate;
    address public holdingVerifier;
    mapping(address => uint256) public nonces;

    event ProtocolFeeRecipientUpdated(address indexed protocolFeeRecipient);
    event ProtocolFeeRateUpdated(uint256 rate);
    event HoldingVerifierUpdated(address indexed verifier);

    function updateProtocolFeeRecipient(address payable _protocolFeeRecipient) external onlyOwner {
        require(_protocolFeeRecipient != address(0), "Invalid protocol fee recipient");
        protocolFeeRecipient = _protocolFeeRecipient;
        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
    }

    function updateProtocolFeeRate(uint256 _rate) external onlyOwner {
        require(_rate <= 1 ether, "Fee rate exceeds maximum");
        protocolFeeRate = _rate;
        emit ProtocolFeeRateUpdated(_rate);
    }

    function updateHoldingVerifier(address _verifier) external onlyOwner {
        require(_verifier != address(0), "Invalid verifier address");
        holdingVerifier = _verifier;
        emit HoldingVerifierUpdated(_verifier);
    }

    function calculateHoldingReward(
        uint256 baseAmount,
        uint256 rewardRatio,
        uint256 nonce,
        bytes memory signature
    ) public returns (uint256) {
        if (signature.length == 0) return 0;
        require(rewardRatio <= 1 ether, "Reward ratio too high");
        require(nonces[msg.sender] == nonce, "Invalid nonce");

        bytes32 hash = keccak256(
            abi.encodePacked(address(this), block.chainid, msg.sender, baseAmount, rewardRatio, nonce)
        );
        bytes32 ethSignedHash = hash.toEthSignedMessageHash();

        address signer = ethSignedHash.recover(signature);
        require(signer == holdingVerifier, "Invalid verifier");

        nonces[msg.sender]++;

        return (baseAmount * rewardRatio) / 1 ether;
    }
}
