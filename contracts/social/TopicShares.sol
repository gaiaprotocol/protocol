// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/Address.sol";
import "./HoldingRewardsBase.sol";
import "../libraries/PricingLib.sol";

contract TopicShares is HoldingRewardsBase {
    using Address for address payable;

    uint256 private constant ACC_FEE_PRECISION = 1e4;
    uint256 public priceIncrementPerShare;
    uint256 public holderFeeRate;

    struct Topic {
        uint256 supply;
        uint256 accFeePerUnit;
    }

    struct Holder {
        uint256 balance;
        int256 feeDebt;
    }

    mapping(bytes32 => Topic) public topics;
    mapping(bytes32 => mapping(address => Holder)) public holders;

    event HolderFeeRateUpdated(uint256 rate);
    event TradeExecuted(
        address indexed trader,
        bytes32 indexed topic,
        bool indexed isBuy,
        uint256 amount,
        uint256 price,
        uint256 protocolFee,
        uint256 holderFee,
        uint256 holdingReward,
        uint256 supply
    );
    event HolderFeeClaimed(address indexed holder, bytes32 indexed topic, uint256 fee);

    function initialize(
        address payable _protocolFeeRecipient,
        uint256 _protocolFeeRate,
        uint256 _holderFeeRate,
        uint256 _priceIncrementPerShare,
        address _holdingVerifier
    ) external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        require(_protocolFeeRecipient != address(0), "Invalid protocol fee recipient");
        require(_holdingVerifier != address(0), "Invalid verifier address");

        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeRate = _protocolFeeRate;
        holderFeeRate = _holderFeeRate;
        priceIncrementPerShare = _priceIncrementPerShare;
        holdingVerifier = _holdingVerifier;

        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
        emit ProtocolFeeRateUpdated(_protocolFeeRate);
        emit HolderFeeRateUpdated(_holderFeeRate);
        emit HoldingVerifierUpdated(_holdingVerifier);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setHolderFeeRate(uint256 _rate) external onlyOwner {
        require(_rate <= 1 ether, "Fee rate exceeds maximum");
        holderFeeRate = _rate;
        emit HolderFeeRateUpdated(_rate);
    }

    function getPrice(uint256 _supply, uint256 amount) public view returns (uint256) {
        return PricingLib.getPrice(_supply, amount, priceIncrementPerShare, 1);
    }

    function getBuyPrice(bytes32 topic, uint256 amount) public view returns (uint256) {
        return PricingLib.getBuyPrice(topics[topic].supply, amount, priceIncrementPerShare, 1);
    }

    function getSellPrice(bytes32 topic, uint256 amount) public view returns (uint256) {
        return PricingLib.getSellPrice(topics[topic].supply, amount, priceIncrementPerShare, 1);
    }

    function getBuyPriceAfterFee(bytes32 topic, uint256 amount) external view returns (uint256) {
        uint256 price = getBuyPrice(topic, amount);
        uint256 protocolFee = ((price * protocolFeeRate) / 1 ether);
        uint256 holderFee = ((price * holderFeeRate) / 1 ether);
        return price + protocolFee + holderFee;
    }

    function getSellPriceAfterFee(bytes32 topic, uint256 amount) external view returns (uint256) {
        uint256 price = getSellPrice(topic, amount);
        uint256 protocolFee = ((price * protocolFeeRate) / 1 ether);
        uint256 holderFee = ((price * holderFeeRate) / 1 ether);
        return price - protocolFee - holderFee;
    }

    function buy(
        bytes32 topic,
        uint256 amount,
        uint256 rewardRatio,
        uint256 holdingRewardNonce,
        bytes memory holdingRewardSignature
    ) external payable nonReentrant {
        Topic memory t = topics[topic];
        uint256 price = getBuyPrice(topic, amount);

        uint256 rawProtocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 holdingReward = calculateHoldingReward(
            rawProtocolFee,
            rewardRatio,
            holdingRewardNonce,
            holdingRewardSignature
        );
        uint256 protocolFee = rawProtocolFee - holdingReward;
        uint256 holderFee = ((price * holderFeeRate) / 1 ether) + holdingReward;

        require(msg.value >= price + protocolFee + holderFee, "Insufficient payment");

        if (t.supply > 0) {
            t.accFeePerUnit += (holderFee * ACC_FEE_PRECISION) / t.supply;
        }

        t.supply += amount;
        topics[topic] = t;

        Holder storage h = holders[topic][msg.sender];
        h.balance += amount;
        h.feeDebt += int256((amount * t.accFeePerUnit) / ACC_FEE_PRECISION);

        protocolFeeRecipient.sendValue(protocolFee);
        if (msg.value > price + protocolFee + holderFee) {
            payable(msg.sender).sendValue(msg.value - price - protocolFee - holderFee);
        }

        emit TradeExecuted(msg.sender, topic, true, amount, price, protocolFee, holderFee, holdingReward, t.supply);
    }

    function sell(
        bytes32 topic,
        uint256 amount,
        uint256 rewardRatio,
        uint256 holdingRewardNonce,
        bytes memory holdingRewardSignature
    ) external nonReentrant {
        Topic memory t = topics[topic];
        Holder storage holder = holders[topic][msg.sender];

        require(holder.balance >= amount, "Insufficient balance");

        uint256 price = getSellPrice(topic, amount);

        uint256 rawProtocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 holdingReward = calculateHoldingReward(
            rawProtocolFee,
            rewardRatio,
            holdingRewardNonce,
            holdingRewardSignature
        );
        uint256 protocolFee = rawProtocolFee - holdingReward;
        uint256 holderFee = ((price * holderFeeRate) / 1 ether) + holdingReward;

        holder.balance -= amount;
        holder.feeDebt -= int256((amount * t.accFeePerUnit) / ACC_FEE_PRECISION);
        t.supply -= amount;

        if (t.supply > 0) {
            t.accFeePerUnit += (holderFee * ACC_FEE_PRECISION) / t.supply;
            topics[topic] = t;

            payable(msg.sender).sendValue(price - protocolFee - holderFee);
            protocolFeeRecipient.sendValue(protocolFee);
        } else {
            topics[topic] = t;

            payable(msg.sender).sendValue(price - protocolFee - holderFee);
            protocolFeeRecipient.sendValue(protocolFee + holderFee);
        }

        emit TradeExecuted(msg.sender, topic, false, amount, price, protocolFee, holderFee, holdingReward, t.supply);
    }

    function claimableHolderFee(bytes32 topic, address holder) public view returns (uint256 claimableFee) {
        Topic memory t = topics[topic];
        Holder memory h = holders[topic][holder];
        int256 accumulatedFee = int256((h.balance * t.accFeePerUnit) / ACC_FEE_PRECISION);
        claimableFee = uint256(accumulatedFee - h.feeDebt);
    }

    function _claimHolderFee(bytes32 topic) private {
        Topic memory t = topics[topic];
        Holder storage holder = holders[topic][msg.sender];
        int256 accumulatedFee = int256((holder.balance * t.accFeePerUnit) / ACC_FEE_PRECISION);
        uint256 claimableFee = uint256(accumulatedFee - holder.feeDebt);
        holder.feeDebt = accumulatedFee;
        payable(msg.sender).sendValue(claimableFee);
        emit HolderFeeClaimed(msg.sender, topic, claimableFee);
    }

    function claimHolderFee(bytes32 topic) external nonReentrant {
        _claimHolderFee(topic);
    }

    function batchClaimableHolderFees(
        bytes32[] memory _topics,
        address holder
    ) external view returns (uint256[] memory claimableFees) {
        claimableFees = new uint256[](_topics.length);
        for (uint256 i = 0; i < _topics.length; i++) {
            claimableFees[i] = claimableHolderFee(_topics[i], holder);
        }
    }

    function batchClaimHolderFees(bytes32[] memory _topics) external nonReentrant {
        for (uint256 i = 0; i < _topics.length; i++) {
            _claimHolderFee(_topics[i]);
        }
    }
}
