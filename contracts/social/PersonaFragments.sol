// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Address.sol";
import "./HoldingRewardsBase.sol";
import "../libraries/PricingLib.sol";

contract PersonaFragments is HoldingRewardsBase {
    using Address for address payable;

    uint256 public priceIncrementPerFragment;
    uint256 public personaOwnerFeeRate;

    mapping(address => mapping(address => uint256)) public balance;
    mapping(address => uint256) public supply;

    event PersonaOwnerFeeRateUpdated(uint256 rate);
    event TradeExecuted(
        address indexed trader,
        address indexed persona,
        bool indexed isBuy,
        uint256 amount,
        uint256 price,
        uint256 protocolFee,
        uint256 personaFee,
        uint256 holdingReward,
        uint256 supply
    );

    function initialize(
        address payable _protocolFeeRecipient,
        uint256 _protocolFeeRate,
        uint256 _personaOwnerFeeRate,
        uint256 _priceIncrementPerFragment,
        address _holdingVerifier
    ) external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        require(_protocolFeeRecipient != address(0), "Invalid protocol fee recipient");
        require(_holdingVerifier != address(0), "Invalid verifier address");

        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeRate = _protocolFeeRate;
        personaOwnerFeeRate = _personaOwnerFeeRate;
        priceIncrementPerFragment = _priceIncrementPerFragment;
        holdingVerifier = _holdingVerifier;

        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
        emit ProtocolFeeRateUpdated(_protocolFeeRate);
        emit PersonaOwnerFeeRateUpdated(_personaOwnerFeeRate);
        emit HoldingVerifierUpdated(_holdingVerifier);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setPersonaOwnerFeeRate(uint256 _rate) external onlyOwner {
        require(_rate <= 1 ether, "Fee rate exceeds maximum");
        personaOwnerFeeRate = _rate;
        emit PersonaOwnerFeeRateUpdated(_rate);
    }

    function getPrice(uint256 _supply, uint256 amount) public view returns (uint256) {
        return PricingLib.getPrice(_supply, amount, priceIncrementPerFragment, 1);
    }

    function getBuyPrice(address persona, uint256 amount) public view returns (uint256) {
        return PricingLib.getBuyPrice(supply[persona], amount, priceIncrementPerFragment, 1);
    }

    function getSellPrice(address persona, uint256 amount) public view returns (uint256) {
        return PricingLib.getSellPrice(supply[persona], amount, priceIncrementPerFragment, 1);
    }

    function getBuyPriceAfterFee(address persona, uint256 amount) external view returns (uint256) {
        uint256 price = getBuyPrice(persona, amount);
        uint256 protocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 personaFee = (price * personaOwnerFeeRate) / 1 ether;
        return price + protocolFee + personaFee;
    }

    function getSellPriceAfterFee(address persona, uint256 amount) external view returns (uint256) {
        uint256 price = getSellPrice(persona, amount);
        uint256 protocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 personaFee = (price * personaOwnerFeeRate) / 1 ether;
        return price - protocolFee - personaFee;
    }

    function executeTrade(
        address persona,
        uint256 amount,
        uint256 price,
        bool isBuy,
        uint256 rewardRatio,
        uint256 holdingRewardNonce,
        bytes memory holdingRewardSignature
    ) private nonReentrant {
        uint256 rawProtocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 holdingReward = calculateHoldingReward(
            rawProtocolFee,
            rewardRatio,
            holdingRewardNonce,
            holdingRewardSignature
        );
        uint256 protocolFee = rawProtocolFee - holdingReward;
        uint256 personaFee = ((price * personaOwnerFeeRate) / 1 ether) + holdingReward;

        if (isBuy) {
            require(msg.value >= price + protocolFee + personaFee, "Insufficient payment");
            protocolFeeRecipient.sendValue(protocolFee);
            payable(persona).sendValue(personaFee);
            if (msg.value > price + protocolFee + personaFee) {
                payable(msg.sender).sendValue(msg.value - price - protocolFee - personaFee);
            }

            balance[persona][msg.sender] += amount;
            supply[persona] += amount;
        } else {
            require(balance[persona][msg.sender] >= amount, "Insufficient balance");
            payable(msg.sender).sendValue(price - protocolFee - personaFee);
            protocolFeeRecipient.sendValue(protocolFee);
            payable(persona).sendValue(personaFee);
            
            balance[persona][msg.sender] -= amount;
            supply[persona] -= amount;
        }

        emit TradeExecuted(
            msg.sender,
            persona,
            isBuy,
            amount,
            price,
            protocolFee,
            personaFee,
            holdingReward,
            supply[persona]
        );
    }

    function buy(
        address persona,
        uint256 amount,
        uint256 rewardRatio,
        uint256 holdingRewardNonce,
        bytes memory holdingRewardSignature
    ) external payable {
        uint256 price = getBuyPrice(persona, amount);
        executeTrade(persona, amount, price, true, rewardRatio, holdingRewardNonce, holdingRewardSignature);
    }

    function sell(
        address persona,
        uint256 amount,
        uint256 rewardRatio,
        uint256 holdingRewardNonce,
        bytes memory holdingRewardSignature
    ) external {
        uint256 price = getSellPrice(persona, amount);
        executeTrade(persona, amount, price, false, rewardRatio, holdingRewardNonce, holdingRewardSignature);
    }
}
