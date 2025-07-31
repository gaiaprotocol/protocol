// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./Material.sol";
import "../libraries/PricingLib.sol";

contract MaterialFactory is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using Address for address payable;

    uint256 public priceIncrement;
    address payable public protocolFeeRecipient;
    uint256 public protocolFeeRate;
    uint256 public materialOwnerFeeRate;

    mapping(address => bool) public isMaterial;
    mapping(address => bool) public tradingOpened;

    event ProtocolFeeRecipientUpdated(address indexed protocolFeeRecipient);
    event ProtocolFeeRateUpdated(uint256 rate);
    event MaterialOwnerFeeRateUpdated(uint256 rate);
    event MaterialCreated(
        address indexed materialOwner,
        address indexed materialAddress,
        string name,
        string symbol,
        bytes32 metadataHash
    );
    event MaterialDeleted(address indexed materialAddress);
    event TradingOpened(address indexed materialAddress);

    event TradeExecuted(
        address indexed trader,
        address indexed materialAddress,
        bool indexed isBuy,
        uint256 amount,
        uint256 price,
        uint256 protocolFee,
        uint256 materialOwnerFee,
        uint256 supply
    );

    function initialize(
        address payable _protocolFeeRecipient,
        uint256 _protocolFeeRate,
        uint256 _materialOwnerFeeRate,
        uint256 _priceIncrement
    ) external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeRate = _protocolFeeRate;
        materialOwnerFeeRate = _materialOwnerFeeRate;
        priceIncrement = _priceIncrement;

        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
        emit ProtocolFeeRateUpdated(_protocolFeeRate);
        emit MaterialOwnerFeeRateUpdated(_materialOwnerFeeRate);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function updateProtocolFeeRecipient(address payable _protocolFeeRecipient) external onlyOwner {
        require(_protocolFeeRecipient != address(0), "Invalid protocol fee recipient address");
        protocolFeeRecipient = _protocolFeeRecipient;
        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
    }

    function updateProtocolFeeRate(uint256 _rate) external onlyOwner {
        require(_rate <= 1 ether, "Fee rate exceeds maximum");
        protocolFeeRate = _rate;
        emit ProtocolFeeRateUpdated(_rate);
    }

    function updateMaterialOwnerFeeRate(uint256 _rate) external onlyOwner {
        require(_rate <= 1 ether, "Fee rate exceeds maximum");
        materialOwnerFeeRate = _rate;
        emit MaterialOwnerFeeRateUpdated(_rate);
    }

    function createMaterial(string memory name, string memory symbol, bytes32 metadataHash) public returns (address) {
        Material newMaterial = new Material(msg.sender, name, symbol);
        isMaterial[address(newMaterial)] = true;
        emit MaterialCreated(msg.sender, address(newMaterial), name, symbol, metadataHash);
        return address(newMaterial);
    }

    modifier onlyMaterial(address materialAddress) {
        require(isMaterial[materialAddress], "Not a material");
        _;
    }

    function openTrading(address materialAddress) external onlyMaterial(materialAddress) {
        Material material = Material(materialAddress);
        require(material.owner() == msg.sender, "Not material owner");
        require(!tradingOpened[materialAddress], "Trading already opened");

        tradingOpened[materialAddress] = true;
        emit TradingOpened(materialAddress);
    }

    function deleteMaterial(address materialAddress) external onlyMaterial(materialAddress) {
        Material material = Material(materialAddress);
        require(material.owner() == msg.sender, "Not material owner");
        require(material.totalSupply() == 0, "Supply must be zero");

        material.deleteMaterial();
        delete tradingOpened[materialAddress];
        emit MaterialDeleted(materialAddress);
    }

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

    function _sendMaterialOwnerFee(address owner, uint256 amount) private {
        (bool success, ) = payable(owner).call{value: amount}("");
        if (!success) protocolFeeRecipient.sendValue(amount);
    }

    function executeTrade(
        address materialAddress,
        uint256 amount,
        uint256 price,
        bool isBuy
    ) private onlyMaterial(materialAddress) nonReentrant {
        Material material = Material(materialAddress);
        require(material.owner() == msg.sender || tradingOpened[materialAddress], "Trading is not opened yet");

        uint256 protocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 materialOwnerFee = (price * materialOwnerFeeRate) / 1 ether;

        if (isBuy) {
            require(msg.value >= price + protocolFee + materialOwnerFee, "Insufficient payment");

            material.mint(msg.sender, amount);
            protocolFeeRecipient.sendValue(protocolFee);
            _sendMaterialOwnerFee(material.owner(), materialOwnerFee);

            if (msg.value > price + protocolFee + materialOwnerFee) {
                uint256 refund = msg.value - price - protocolFee - materialOwnerFee;
                payable(msg.sender).sendValue(refund);
            }
        } else {
            require(material.balanceOf(msg.sender) >= amount, "Insufficient balance");
            material.burn(msg.sender, amount);

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
            material.totalSupply()
        );
    }

    function buy(address materialAddress, uint256 amount) external payable {
        uint256 price = getBuyPrice(materialAddress, amount);
        executeTrade(materialAddress, amount, price, true);
    }

    function sell(address materialAddress, uint256 amount) external {
        uint256 price = getSellPrice(materialAddress, amount);
        executeTrade(materialAddress, amount, price, false);
    }
}
