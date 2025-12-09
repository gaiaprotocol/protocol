// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {Material} from "./Material.sol";
import {PricingLib} from "../libraries/PricingLib.sol";

contract MaterialFactory is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using Address for address payable;

    // ------------------------------------------------------------------
    // Custom Errors (gas-efficient replacements for require statements)
    // ------------------------------------------------------------------
    error InvalidProtocolFeeRecipient();
    error FeeRateExceedsMaximum();
    error NotMaterial();
    error NotMaterialOwner();
    error TradingAlreadyOpened();
    error TradingNotOpenedYet();
    error SupplyNotZero();
    error InsufficientPayment();
    error InsufficientBalance();
    error ZeroAmount();
    error ZeroPrice();

    // ------------------------------------------------------------------
    // Configuration
    // ------------------------------------------------------------------
    uint256 public priceIncrement; // Linear increment (wei) per token
    address payable public protocolFeeRecipient;
    uint256 public protocolFeeRate; // 1 ether == 100%
    uint256 public materialOwnerFeeRate; // 1 ether == 100%

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    mapping(address => bool) public isMaterial;
    mapping(address => bool) public tradingOpened;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event ProtocolFeeRecipientUpdated(address indexed protocolFeeRecipient);
    event ProtocolFeeRateUpdated(uint256 rate);
    event MaterialOwnerFeeRateUpdated(uint256 rate);

    event MaterialCreated(
        address indexed materialOwner, address indexed materialAddress, string name, string symbol, bytes32 metadataHash
    );
    event MaterialDeleted(address indexed materialAddress);
    event TradingOpened(address indexed materialAddress);

    /**
     * @param trader          Address performing the trade
     * @param materialAddress Address of the Material token
     * @param isBuy           True if buy, false if sell
     * @param amount          Amount of tokens traded
     * @param price           Trade price before fees
     * @param protocolFee     Protocol fee amount
     * @param materialOwnerFee Fee paid to the material owner
     * @param supply          Total supply of the material after the trade
     * @param traderBalance   Trader's token balance after the trade
     */
    event TradeExecuted(
        address indexed trader,
        address indexed materialAddress,
        bool indexed isBuy,
        uint256 amount,
        uint256 price,
        uint256 protocolFee,
        uint256 materialOwnerFee,
        uint256 supply,
        uint256 traderBalance
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
        uint256 _materialOwnerFeeRate,
        uint256 _priceIncrement
    ) external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        if (_protocolFeeRecipient == address(0)) {
            revert InvalidProtocolFeeRecipient();
        }
        if (_protocolFeeRate > 1 ether || _materialOwnerFeeRate > 1 ether) {
            revert FeeRateExceedsMaximum();
        }

        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeRate = _protocolFeeRate;
        materialOwnerFeeRate = _materialOwnerFeeRate;
        priceIncrement = _priceIncrement;

        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
        emit ProtocolFeeRateUpdated(_protocolFeeRate);
        emit MaterialOwnerFeeRateUpdated(_materialOwnerFeeRate);
    }

    /// @dev Authorizes implementation upgrades (owner-only).
    function _authorizeUpgrade(address) internal override onlyOwner {
        // No extra logic — access control enforced by `onlyOwner`.
    }

    // ------------------------------------------------------------------
    // Admin setters
    // ------------------------------------------------------------------
    function updateProtocolFeeRecipient(address payable _protocolFeeRecipient) external onlyOwner {
        if (_protocolFeeRecipient == address(0)) {
            revert InvalidProtocolFeeRecipient();
        }
        protocolFeeRecipient = _protocolFeeRecipient;
        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
    }

    function updateProtocolFeeRate(uint256 _rate) external onlyOwner {
        if (_rate > 1 ether) revert FeeRateExceedsMaximum();
        protocolFeeRate = _rate;
        emit ProtocolFeeRateUpdated(_rate);
    }

    function updateMaterialOwnerFeeRate(uint256 _rate) external onlyOwner {
        if (_rate > 1 ether) revert FeeRateExceedsMaximum();
        materialOwnerFeeRate = _rate;
        emit MaterialOwnerFeeRateUpdated(_rate);
    }

    // ------------------------------------------------------------------
    // Material lifecycle
    // ------------------------------------------------------------------
    function createMaterial(string memory name, string memory symbol, bytes32 metadataHash) public returns (address) {
        Material newMaterial = new Material(msg.sender, name, symbol);
        isMaterial[address(newMaterial)] = true;

        emit MaterialCreated(msg.sender, address(newMaterial), name, symbol, metadataHash);
        return address(newMaterial);
    }

    modifier onlyMaterial(address materialAddress) {
        if (!isMaterial[materialAddress]) revert NotMaterial();
        _;
    }

    function openTrading(address materialAddress) external onlyMaterial(materialAddress) {
        Material material = Material(materialAddress);
        if (material.owner() != msg.sender) revert NotMaterialOwner();
        if (tradingOpened[materialAddress]) revert TradingAlreadyOpened();

        tradingOpened[materialAddress] = true;
        emit TradingOpened(materialAddress);
    }

    function deleteMaterial(address materialAddress) external onlyMaterial(materialAddress) {
        Material material = Material(materialAddress);
        if (material.owner() != msg.sender) revert NotMaterialOwner();
        if (material.totalSupply() != 0) revert SupplyNotZero();

        material.deleteMaterial();
        delete tradingOpened[materialAddress];

        emit MaterialDeleted(materialAddress);
    }

    // ------------------------------------------------------------------
    // Pricing helpers
    // ------------------------------------------------------------------
    function getPrice(uint256 supply, uint256 amount) public view returns (uint256) {
        return PricingLib.getPrice(supply, amount, priceIncrement, 1 ether);
    }

    function getBuyPrice(address materialAddress, uint256 amount) public view returns (uint256) {
        Material material = Material(materialAddress);
        return PricingLib.getBuyPrice(material.totalSupply(), amount, priceIncrement, 1 ether);
    }

    function getSellPrice(address materialAddress, uint256 amount) public view returns (uint256) {
        Material material = Material(materialAddress);
        return PricingLib.getSellPrice(material.totalSupply(), amount, priceIncrement, 1 ether);
    }

    function getBuyPriceAfterFee(address materialAddress, uint256 amount) external view returns (uint256) {
        uint256 price = getBuyPrice(materialAddress, amount);
        uint256 protocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 materialOwnerFee = (price * materialOwnerFeeRate) / 1 ether;
        return price + protocolFee + materialOwnerFee;
    }

    function getSellPriceAfterFee(address materialAddress, uint256 amount) external view returns (uint256) {
        uint256 price = getSellPrice(materialAddress, amount);
        uint256 protocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 materialOwnerFee = (price * materialOwnerFeeRate) / 1 ether;
        return price - protocolFee - materialOwnerFee;
    }

    // ------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------
    function _sendMaterialOwnerFee(address owner, uint256 amount) private {
        (bool success,) = payable(owner).call{value: amount}("");
        if (!success) {
            protocolFeeRecipient.sendValue(amount);
        }
    }

    function executeTrade(address materialAddress, uint256 amount, uint256 price, bool isBuy)
        private
        onlyMaterial(materialAddress)
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (price == 0) revert ZeroPrice();

        Material material = Material(materialAddress);

        // Check if trading is allowed (either owner is trading, or trading is opened)
        if (!(material.owner() == msg.sender || tradingOpened[materialAddress])) {
            revert TradingNotOpenedYet();
        }

        uint256 protocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 materialOwnerFee = (price * materialOwnerFeeRate) / 1 ether;
        uint256 traderBalanceAfter;

        if (isBuy) {
            uint256 totalCost = price + protocolFee + materialOwnerFee;
            if (msg.value < totalCost) revert InsufficientPayment();

            material.mint(msg.sender, amount);
            traderBalanceAfter = material.balanceOf(msg.sender);

            protocolFeeRecipient.sendValue(protocolFee);
            _sendMaterialOwnerFee(material.owner(), materialOwnerFee);

            if (msg.value > totalCost) {
                payable(msg.sender).sendValue(msg.value - totalCost);
            }
        } else {
            if (material.balanceOf(msg.sender) < amount) {
                revert InsufficientBalance();
            }

            material.burn(msg.sender, amount);
            traderBalanceAfter = material.balanceOf(msg.sender);

            uint256 netAmount = price - protocolFee - materialOwnerFee;

            payable(msg.sender).sendValue(netAmount);
            protocolFeeRecipient.sendValue(protocolFee);
            _sendMaterialOwnerFee(material.owner(), materialOwnerFee);
        }

        emit TradeExecuted(
            msg.sender,
            materialAddress,
            isBuy,
            amount,
            price,
            protocolFee,
            materialOwnerFee,
            material.totalSupply(),
            traderBalanceAfter
        );
    }

    // ------------------------------------------------------------------
    // External trading API
    // ------------------------------------------------------------------
    function buy(address materialAddress, uint256 amount) external payable {
        uint256 price = getBuyPrice(materialAddress, amount);
        executeTrade(materialAddress, amount, price, true);
    }

    function sell(address materialAddress, uint256 amount) external {
        uint256 price = getSellPrice(materialAddress, amount);
        executeTrade(materialAddress, amount, price, false);
    }
}
