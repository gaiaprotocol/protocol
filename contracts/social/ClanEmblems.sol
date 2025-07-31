// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {HoldingRewardsBase} from "./HoldingRewardsBase.sol";
import {PricingLib} from "../libraries/PricingLib.sol";

contract ClanEmblems is HoldingRewardsBase {
    using Address for address payable;

    // ------------------------------------------------------------------
    // Custom Errors (gas‑efficient reverts)
    // ------------------------------------------------------------------
    error InvalidProtocolFeeRecipient();
    error InvalidVerifierAddress();
    error FeeRateExceedsMaximum();
    error MustBuyAtLeastOneEmblem();
    error ClanDoesNotExist();
    error NotClanOwner();
    error NewOwnerMustBeClanMember();
    error NoFeesToWithdraw();
    error OwnerMustHoldEntireSupply();
    error InsufficientPayment();
    error InsufficientBalance();
    error OwnerCannotSellAllEmblems();

    // ------------------------------------------------------------------
    // Config
    // ------------------------------------------------------------------
    uint256 public priceIncrementPerEmblem; // Linear increment (wei) per emblem
    uint256 public clanFeeRate; // 1 ether == 100%

    struct Clan {
        address owner;
        uint256 accumulatedFees;
    }

    uint256 public nextClanId;
    mapping(uint256 => Clan) public clans;
    mapping(uint256 => mapping(address => uint256)) public balance;
    mapping(uint256 => uint256) public supply;

    // Per‑user clan tracking (for `sharesAnyClan` helper)
    mapping(address => uint256[]) public userClans;
    mapping(address => mapping(uint256 => uint256)) public userClanIndex;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event ClanFeeRateUpdated(uint256 rate);
    event ClanCreated(address indexed clanOwner, uint256 indexed clanId, bytes32 metadataHash);
    event ClanDeleted(uint256 indexed clanId);
    event ClanOwnershipTransferred(uint256 indexed clanId, address indexed previousOwner, address indexed newOwner);
    event FeesWithdrawn(uint256 indexed clanId, uint256 amount);
    event TradeExecuted(
        address indexed trader,
        uint256 indexed clanId,
        bool indexed isBuy,
        uint256 amount,
        uint256 price,
        uint256 protocolFee,
        uint256 clanFee,
        uint256 holdingReward,
        uint256 supply
    );

    // ------------------------------------------------------------------
    // Initializer
    // ------------------------------------------------------------------
    function initialize(
        address payable _protocolFeeRecipient,
        uint256 _protocolFeeRate,
        uint256 _clanFeeRate,
        uint256 _priceIncrementPerEmblem,
        address _holdingVerifier
    ) external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        if (_protocolFeeRecipient == address(0)) revert InvalidProtocolFeeRecipient();
        if (_holdingVerifier == address(0)) revert InvalidVerifierAddress();
        if (_clanFeeRate > 1 ether || _protocolFeeRate > 1 ether) revert FeeRateExceedsMaximum();

        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeRate = _protocolFeeRate;
        clanFeeRate = _clanFeeRate;
        priceIncrementPerEmblem = _priceIncrementPerEmblem;
        holdingVerifier = _holdingVerifier;

        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
        emit ProtocolFeeRateUpdated(_protocolFeeRate);
        emit ClanFeeRateUpdated(_clanFeeRate);
        emit HoldingVerifierUpdated(_holdingVerifier);
    }

    /// @dev Authorizes implementation upgrades (owner-only).
    function _authorizeUpgrade(address /*newImplementation*/) internal override onlyOwner {
        // No extra logic — access control enforced by `onlyOwner`.
    }

    // ------------------------------------------------------------------
    // Admin setters
    // ------------------------------------------------------------------
    function setClanFeeRate(uint256 _rate) external onlyOwner {
        if (_rate > 1 ether) revert FeeRateExceedsMaximum();
        clanFeeRate = _rate;
        emit ClanFeeRateUpdated(_rate);
    }

    // ------------------------------------------------------------------
    // Clan lifecycle
    // ------------------------------------------------------------------
    function createClan(
        bytes32 metadataHash,
        uint256 emblemAmount,
        uint256 rewardRatio,
        uint256 holdingRewardNonce,
        bytes memory holdingRewardSignature
    ) external payable returns (uint256 clanId) {
        if (emblemAmount == 0) revert MustBuyAtLeastOneEmblem();

        clanId = nextClanId++;
        clans[clanId].owner = msg.sender;

        uint256 price = getBuyPrice(clanId, emblemAmount);
        executeTrade(
            TradeParams({
                clanId: clanId,
                amount: emblemAmount,
                price: price,
                isBuy: true,
                rewardRatio: rewardRatio,
                holdingRewardNonce: holdingRewardNonce,
                holdingRewardSignature: holdingRewardSignature
            })
        );

        emit ClanCreated(msg.sender, clanId, metadataHash);
    }

    function transferClanOwnership(uint256 clanId, address newOwner) external {
        if (clans[clanId].owner != msg.sender) revert NotClanOwner();
        if (balance[clanId][newOwner] == 0) revert NewOwnerMustBeClanMember();

        address previousOwner = clans[clanId].owner;
        clans[clanId].owner = newOwner;

        emit ClanOwnershipTransferred(clanId, previousOwner, newOwner);
    }

    function withdrawFees(uint256 clanId) public {
        if (clans[clanId].owner != msg.sender) revert NotClanOwner();
        uint256 amount = clans[clanId].accumulatedFees;
        if (amount == 0) revert NoFeesToWithdraw();

        clans[clanId].accumulatedFees = 0;
        payable(msg.sender).sendValue(amount);

        emit FeesWithdrawn(clanId, amount);
    }

    function deleteClan(
        uint256 clanId,
        uint256 rewardRatio,
        uint256 holdingRewardNonce,
        bytes memory holdingRewardSignature
    ) external {
        if (clans[clanId].owner != msg.sender) revert NotClanOwner();

        uint256 _supply = supply[clanId];
        if (balance[clanId][msg.sender] != _supply) revert OwnerMustHoldEntireSupply();

        uint256 price = getSellPrice(clanId, _supply);
        executeTrade(
            TradeParams({
                clanId: clanId,
                amount: _supply,
                price: price,
                isBuy: false,
                rewardRatio: rewardRatio,
                holdingRewardNonce: holdingRewardNonce,
                holdingRewardSignature: holdingRewardSignature
            })
        );

        withdrawFees(clanId);

        delete clans[clanId];
        emit ClanDeleted(clanId);
    }

    // ------------------------------------------------------------------
    // Pricing helpers
    // ------------------------------------------------------------------
    function getPrice(uint256 _supply, uint256 amount) public view returns (uint256) {
        return PricingLib.getPrice(_supply, amount, priceIncrementPerEmblem, 1);
    }

    function getBuyPrice(uint256 clanId, uint256 amount) public view returns (uint256) {
        return PricingLib.getBuyPrice(supply[clanId], amount, priceIncrementPerEmblem, 1);
    }

    function getSellPrice(uint256 clanId, uint256 amount) public view returns (uint256) {
        return PricingLib.getSellPrice(supply[clanId], amount, priceIncrementPerEmblem, 1);
    }

    function getBuyPriceAfterFee(uint256 clanId, uint256 amount) external view returns (uint256) {
        uint256 price = getBuyPrice(clanId, amount);
        uint256 protocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 clanFee = (price * clanFeeRate) / 1 ether;
        return price + protocolFee + clanFee;
    }

    function getSellPriceAfterFee(uint256 clanId, uint256 amount) external view returns (uint256) {
        uint256 price = getSellPrice(clanId, amount);
        uint256 protocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 clanFee = (price * clanFeeRate) / 1 ether;
        return price - protocolFee - clanFee;
    }

    // ------------------------------------------------------------------
    // Core trade execution
    // ------------------------------------------------------------------
    struct TradeParams {
        uint256 clanId;
        uint256 amount;
        uint256 price;
        bool isBuy;
        uint256 rewardRatio;
        uint256 holdingRewardNonce;
        bytes holdingRewardSignature;
    }

    function executeTrade(TradeParams memory p) private nonReentrant {
        if (clans[p.clanId].owner == address(0)) revert ClanDoesNotExist();

        uint256 rawProtocolFee = (p.price * protocolFeeRate) / 1 ether;
        uint256 holdingReward = calculateHoldingReward(
            rawProtocolFee,
            p.rewardRatio,
            p.holdingRewardNonce,
            p.holdingRewardSignature
        );
        uint256 protocolFee = rawProtocolFee - holdingReward;
        uint256 clanFee = ((p.price * clanFeeRate) / 1 ether) + holdingReward;

        if (p.isBuy) {
            uint256 totalCost = p.price + protocolFee + clanFee;
            if (msg.value < totalCost) revert InsufficientPayment();

            if (balance[p.clanId][msg.sender] == 0) _addUserClan(msg.sender, p.clanId);

            balance[p.clanId][msg.sender] += p.amount;
            supply[p.clanId] += p.amount;

            protocolFeeRecipient.sendValue(protocolFee);
            clans[p.clanId].accumulatedFees += clanFee;

            if (msg.value > totalCost) payable(msg.sender).sendValue(msg.value - totalCost);
        } else {
            if (balance[p.clanId][msg.sender] < p.amount) revert InsufficientBalance();

            // Prevent owner from dumping entire supply except via deleteClan
            if (msg.sender == clans[p.clanId].owner && balance[p.clanId][msg.sender] == p.amount)
                revert OwnerCannotSellAllEmblems();

            balance[p.clanId][msg.sender] -= p.amount;
            supply[p.clanId] -= p.amount;

            if (balance[p.clanId][msg.sender] == 0) _removeUserClan(msg.sender, p.clanId);

            payable(msg.sender).sendValue(p.price - protocolFee - clanFee);
            protocolFeeRecipient.sendValue(protocolFee);
            clans[p.clanId].accumulatedFees += clanFee;
        }

        emit TradeExecuted(
            msg.sender,
            p.clanId,
            p.isBuy,
            p.amount,
            p.price,
            protocolFee,
            clanFee,
            holdingReward,
            supply[p.clanId]
        );
    }

    // ------------------------------------------------------------------
    // External trading API
    // ------------------------------------------------------------------
    function buy(
        uint256 clanId,
        uint256 amount,
        uint256 rewardRatio,
        uint256 holdingRewardNonce,
        bytes memory holdingRewardSignature
    ) external payable {
        uint256 price = getBuyPrice(clanId, amount);
        executeTrade(
            TradeParams({
                clanId: clanId,
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
        uint256 clanId,
        uint256 amount,
        uint256 rewardRatio,
        uint256 holdingRewardNonce,
        bytes memory holdingRewardSignature
    ) external {
        uint256 price = getSellPrice(clanId, amount);
        executeTrade(
            TradeParams({
                clanId: clanId,
                amount: amount,
                price: price,
                isBuy: false,
                rewardRatio: rewardRatio,
                holdingRewardNonce: holdingRewardNonce,
                holdingRewardSignature: holdingRewardSignature
            })
        );
    }

    // ------------------------------------------------------------------
    // Internal helpers for per‑user clan lists
    // ------------------------------------------------------------------
    function _addUserClan(address user, uint256 clanId) internal {
        userClanIndex[user][clanId] = userClans[user].length;
        userClans[user].push(clanId);
    }

    function _removeUserClan(address user, uint256 clanId) internal {
        uint256 index = userClanIndex[user][clanId];
        uint256 lastIndex = userClans[user].length - 1;

        if (index != lastIndex) {
            uint256 lastClanId = userClans[user][lastIndex];
            userClans[user][index] = lastClanId;
            userClanIndex[user][lastClanId] = index;
        }

        userClans[user].pop();
        delete userClanIndex[user][clanId];
    }

    // ------------------------------------------------------------------
    // View helper
    // ------------------------------------------------------------------
    function sharesAnyClan(address userA, address userB) external view returns (bool) {
        uint256[] memory clansA = userClans[userA];
        uint256 len = clansA.length;
        for (uint256 i = 0; i < len; ++i) {
            if (balance[clansA[i]][userB] > 0) return true;
        }
        return false;
    }
}
