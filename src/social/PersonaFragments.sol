// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {HoldingRewardsBase} from "./HoldingRewardsBase.sol";
import {PricingLib} from "../libraries/PricingLib.sol";

contract PersonaFragments is HoldingRewardsBase {
    using Address for address payable;

    // ------------------------------------------------------------------
    // Custom Errors (gas-efficient reverts)
    // ------------------------------------------------------------------
    error InsufficientPayment();
    error InsufficientBalance();
    error InvalidAmount();

    // ------------------------------------------------------------------
    // Config
    // ------------------------------------------------------------------
    uint256 public priceIncrementPerFragment; // Linear increment (wei) per fragment
    uint256 public personaOwnerFeeRate; // 1 ether == 100%

    mapping(address => mapping(address => uint256)) public balance; // persona → user → amount
    mapping(address => uint256) public supply; // persona → total supply

    // ------------------------------------------------------------------
    // Storage Gap
    // ------------------------------------------------------------------
    // Reserved space for future upgrades of this specific contract
    uint256[50] private __gap;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // Constructor (UUPS best practice)
    // ------------------------------------------------------------------
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Prevent the implementation contract itself from being initialized.
        _disableInitializers();
    }

    // ------------------------------------------------------------------
    // Initializer
    // ------------------------------------------------------------------
    function initialize(
        address payable _protocolFeeRecipient,
        uint256 _protocolFeeRate,
        uint256 _personaOwnerFeeRate,
        uint256 _priceIncrementPerFragment,
        address _holdingVerifier
    ) external initializer {
        // Call parent initializer (Logic encapsulation)
        __HoldingRewardsBase_init(_protocolFeeRecipient, _protocolFeeRate, _holdingVerifier);

        if (_personaOwnerFeeRate > 1 ether) revert FeeRateExceedsMaximum();

        personaOwnerFeeRate = _personaOwnerFeeRate;
        priceIncrementPerFragment = _priceIncrementPerFragment;

        emit PersonaOwnerFeeRateUpdated(_personaOwnerFeeRate);
    }

    /// @dev Authorizes implementation upgrades (owner-only).
    function _authorizeUpgrade(address /*newImplementation*/) internal override onlyOwner {
        // Access control enforced by onlyOwner
    }

    // ------------------------------------------------------------------
    // Admin setters
    // ------------------------------------------------------------------
    function setPersonaOwnerFeeRate(uint256 _rate) external onlyOwner {
        if (_rate > 1 ether) revert FeeRateExceedsMaximum();
        personaOwnerFeeRate = _rate;
        emit PersonaOwnerFeeRateUpdated(_rate);
    }

    // ------------------------------------------------------------------
    // Pricing helpers
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------
    function _sendPersonaFee(address persona, uint256 amount) private {
        // If the persona owner is a contract that cannot receive ETH,
        // send the fee to the protocol recipient instead to prevent DoS.
        (bool success, ) = payable(persona).call{value: amount}("");
        if (!success) protocolFeeRecipient.sendValue(amount);
    }

    struct TradeParams {
        address persona;
        uint256 amount;
        uint256 price;
        bool isBuy;
        uint256 rewardRatio;
        uint256 holdingRewardNonce;
        bytes holdingRewardSignature;
    }

    function executeTrade(TradeParams memory p) private nonReentrant {
        // 1. Calculate raw protocol fee
        uint256 rawProtocolFee = (p.price * protocolFeeRate) / 1 ether;

        // 2. Calculate holding reward
        // Note: calculateHoldingReward no longer uses rawProtocolFee for signature verification,
        // only checks rewardRatio. This makes it safe against price slippage.
        uint256 holdingReward = calculateHoldingReward(
            rawProtocolFee,
            p.rewardRatio,
            p.holdingRewardNonce,
            p.holdingRewardSignature
        );

        // 3. Calculate final fee distribution
        // The holding reward is deducted from the protocol fee and effectively transferred to the user/persona fee logic
        uint256 protocolFee = rawProtocolFee - holdingReward;
        uint256 personaFee = ((p.price * personaOwnerFeeRate) / 1 ether) + holdingReward;

        if (p.isBuy) {
            uint256 totalCost = p.price + protocolFee + personaFee;

            // Check >= to allow for extra ETH sent for slippage/gas
            if (msg.value < totalCost) revert InsufficientPayment();

            protocolFeeRecipient.sendValue(protocolFee);
            _sendPersonaFee(p.persona, personaFee);

            // Refund excess ETH
            if (msg.value > totalCost) {
                payable(msg.sender).sendValue(msg.value - totalCost);
            }

            balance[p.persona][msg.sender] += p.amount;
            supply[p.persona] += p.amount;
        } else {
            if (balance[p.persona][msg.sender] < p.amount) revert InsufficientBalance();

            uint256 proceeds = p.price - protocolFee - personaFee;

            payable(msg.sender).sendValue(proceeds);
            protocolFeeRecipient.sendValue(protocolFee);
            _sendPersonaFee(p.persona, personaFee);

            balance[p.persona][msg.sender] -= p.amount;
            supply[p.persona] -= p.amount;
        }

        emit TradeExecuted(
            msg.sender,
            p.persona,
            p.isBuy,
            p.amount,
            p.price,
            protocolFee,
            personaFee,
            holdingReward,
            supply[p.persona]
        );
    }

    // ------------------------------------------------------------------
    // External trading API
    // ------------------------------------------------------------------
    function buy(
        address persona,
        uint256 amount,
        uint256 rewardRatio,
        uint256 holdingRewardNonce,
        bytes memory holdingRewardSignature
    ) external payable {
        if (amount == 0) revert InvalidAmount();

        uint256 price = getBuyPrice(persona, amount);
        executeTrade(
            TradeParams({
                persona: persona,
                amount: amount,
                price: price,
                isBuy: true,
                rewardRatio: rewardRatio,
                holdingRewardNonce: holdingRewardNonce,
                holdingRewardSignature: holdingRewardSignature
            })
        );
    }

    function sell(
        address persona,
        uint256 amount,
        uint256 rewardRatio,
        uint256 holdingRewardNonce,
        bytes memory holdingRewardSignature
    ) external {
        if (amount == 0) revert InvalidAmount();

        uint256 price = getSellPrice(persona, amount);
        executeTrade(
            TradeParams({
                persona: persona,
                amount: amount,
                price: price,
                isBuy: false,
                rewardRatio: rewardRatio,
                holdingRewardNonce: holdingRewardNonce,
                holdingRewardSignature: holdingRewardSignature
            })
        );
    }
}
