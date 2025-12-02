// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {HoldingRewardsBase} from "./HoldingRewardsBase.sol";
import {PricingLib} from "../libraries/PricingLib.sol";

contract PersonaFragments is HoldingRewardsBase {
    using Address for address payable;

    // ------------------------------------------------------------------
    // Custom Errors
    // ------------------------------------------------------------------
    error InsufficientPayment();
    error InsufficientBalance();
    error InvalidAmount();

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------
    /// @notice Linear increment per fragment for bonding curve pricing
    uint256 public priceIncrementPerFragment;

    /// @notice Fee rate paid to persona owner (1e18 = 100%)
    uint256 public personaOwnerFeeRate;

    /// @notice persona => user => fragment balance
    mapping(address => mapping(address => uint256)) public balance;

    /// @notice persona => total fragment supply
    mapping(address => uint256) public supply;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event PersonaOwnerFeeRateUpdated(uint256 rate);

    /**
     * @notice Fires for every buy/sell operation.
     * @param trader        Address of trader
     * @param persona       Target persona
     * @param isBuy         True if buy, false if sell
     * @param amount        Amount of fragments traded
     * @param price         Base price before fee
     * @param protocolFee   Final protocol fee after reward deduction
     * @param personaFee    Fee distributed to persona owner + holding reward
     * @param holdingReward Reward amount returned to user via signature logic
     * @param supply        Persona supply after the trade
     * @param traderBalance Trader’s balance of persona fragments after the trade
     */
    event TradeExecuted(
        address indexed trader,
        address indexed persona,
        bool indexed isBuy,
        uint256 amount,
        uint256 price,
        uint256 protocolFee,
        uint256 personaFee,
        uint256 holdingReward,
        uint256 supply,
        uint256 traderBalance
    );

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------
    constructor() {
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
        __HoldingRewardsBase_init(_protocolFeeRecipient, _protocolFeeRate, _holdingVerifier);

        if (_personaOwnerFeeRate > 1 ether) revert FeeRateExceedsMaximum();

        personaOwnerFeeRate = _personaOwnerFeeRate;
        priceIncrementPerFragment = _priceIncrementPerFragment;

        emit PersonaOwnerFeeRateUpdated(_personaOwnerFeeRate);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

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
        return price + (price * protocolFeeRate) / 1 ether + (price * personaOwnerFeeRate) / 1 ether;
    }

    function getSellPriceAfterFee(address persona, uint256 amount) external view returns (uint256) {
        uint256 price = getSellPrice(persona, amount);
        return price - (price * protocolFeeRate) / 1 ether - (price * personaOwnerFeeRate) / 1 ether;
    }

    // ------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------
    /**
     * @notice Sends persona fee to persona owner.
     * @dev If persona is a contract that cannot accept ETH, fee goes to protocol fee recipient instead.
     */
    function _sendPersonaFee(address persona, uint256 amount) private {
        (bool success,) = payable(persona).call{value: amount}("");
        if (!success) {
            protocolFeeRecipient.sendValue(amount);
        }
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

    // ------------------------------------------------------------------
    // Trade Execution
    // ------------------------------------------------------------------
    function executeTrade(TradeParams memory p) private nonReentrant {
        uint256 rawProtocolFee = (p.price * protocolFeeRate) / 1 ether;

        // holdingReward is deducted from protocol fee and moved into personaFee
        uint256 holdingReward =
            calculateHoldingReward(rawProtocolFee, p.rewardRatio, p.holdingRewardNonce, p.holdingRewardSignature);

        uint256 protocolFee = rawProtocolFee - holdingReward;
        uint256 personaFee = (p.price * personaOwnerFeeRate) / 1 ether + holdingReward;

        uint256 traderBalanceAfter;

        if (p.isBuy) {
            uint256 totalCost = p.price + protocolFee + personaFee;
            if (msg.value < totalCost) revert InsufficientPayment();

            protocolFeeRecipient.sendValue(protocolFee);
            _sendPersonaFee(p.persona, personaFee);

            if (msg.value > totalCost) {
                payable(msg.sender).sendValue(msg.value - totalCost);
            }

            balance[p.persona][msg.sender] += p.amount;
            supply[p.persona] += p.amount;
        } else {
            if (balance[p.persona][msg.sender] < p.amount) {
                revert InsufficientBalance();
            }

            uint256 proceeds = p.price - protocolFee - personaFee;

            payable(msg.sender).sendValue(proceeds);
            protocolFeeRecipient.sendValue(protocolFee);
            _sendPersonaFee(p.persona, personaFee);

            balance[p.persona][msg.sender] -= p.amount;
            supply[p.persona] -= p.amount;
        }

        traderBalanceAfter = balance[p.persona][msg.sender];

        emit TradeExecuted(
            msg.sender,
            p.persona,
            p.isBuy,
            p.amount,
            p.price,
            protocolFee,
            personaFee,
            holdingReward,
            supply[p.persona],
            traderBalanceAfter
        );
    }

    // ------------------------------------------------------------------
    // Public buy/sell API
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
