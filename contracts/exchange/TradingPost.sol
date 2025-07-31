// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC721HolderUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import {ERC1155HolderUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract TradingPost is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    ERC1155HolderUpgradeable,
    UUPSUpgradeable
{
    using Address for address payable;

    // ---------------------------------------------------------------------
    // Custom Errors (gas-efficient replacements for require statements)
    // ---------------------------------------------------------------------
    error InvalidProtocolFeeRecipient();
    error FeeRateExceedsMaximum();
    error PriceMustBeGreaterThanZero();
    error InvalidQuantity();
    error UnsupportedTokenType();
    error ListingDoesNotExist();
    error OnlySeller();
    error InsufficientPayment();

    // ---------------------------------------------------------------------
    // Protocol configuration
    // ---------------------------------------------------------------------
    address payable public protocolFeeRecipient;
    uint256 public protocolFeeRate; // 1 ether == 100%

    event ProtocolFeeRecipientUpdated(address indexed protocolFeeRecipient);
    event ProtocolFeeRateUpdated(uint256 rate);

    // ---------------------------------------------------------------------
    // Listings
    // ---------------------------------------------------------------------
    enum TokenType {
        ERC721,
        ERC1155
    }

    struct Listing {
        uint256 listingId;
        address seller;
        address nftAddress;
        uint256 tokenId;
        TokenType tokenType;
        uint256 quantity;
        uint256 price;
    }

    uint256 public nextListingId;
    mapping(uint256 => Listing) public listings;

    event ItemListed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftAddress,
        uint256 tokenId,
        TokenType tokenType,
        uint256 quantity,
        uint256 price
    );
    event ListingCancelled(uint256 indexed listingId);
    event ItemSold(uint256 indexed listingId, address indexed buyer, uint256 quantity, uint256 price);

    // ---------------------------------------------------------------------
    // Initializer / Upgradability hooks
    // ---------------------------------------------------------------------
    function initialize(address payable _protocolFeeRecipient, uint256 _protocolFeeRate) external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        if (_protocolFeeRecipient == address(0)) revert InvalidProtocolFeeRecipient();
        if (_protocolFeeRate > 1 ether) revert FeeRateExceedsMaximum();

        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeRate = _protocolFeeRate;

        nextListingId = 1;

        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
        emit ProtocolFeeRateUpdated(_protocolFeeRate);
    }

    /// @dev Authorizes implementation upgrades (owner-only).
    function _authorizeUpgrade(address /*newImplementation*/) internal override onlyOwner {
        // No extra logic — access control enforced by `onlyOwner`.
    }

    // ---------------------------------------------------------------------
    // Admin setters
    // ---------------------------------------------------------------------
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

    // ---------------------------------------------------------------------
    // Listing logic
    // ---------------------------------------------------------------------
    function listItem(
        address nftAddress,
        uint256 tokenId,
        TokenType tokenType,
        uint256 quantity,
        uint256 price
    ) external nonReentrant {
        if (price == 0) revert PriceMustBeGreaterThanZero();

        if (tokenType == TokenType.ERC721) {
            if (quantity != 1) revert InvalidQuantity();
            IERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId);
        } else if (tokenType == TokenType.ERC1155) {
            if (quantity == 0) revert InvalidQuantity();
            IERC1155(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId, quantity, "");
        } else {
            revert UnsupportedTokenType();
        }

        uint256 listingId = nextListingId++;
        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            nftAddress: nftAddress,
            tokenId: tokenId,
            tokenType: tokenType,
            quantity: quantity,
            price: price
        });

        emit ItemListed(listingId, msg.sender, nftAddress, tokenId, tokenType, quantity, price);
    }

    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.seller == address(0)) revert ListingDoesNotExist();
        if (msg.sender != listing.seller) revert OnlySeller();

        if (listing.tokenType == TokenType.ERC721) {
            IERC721(listing.nftAddress).safeTransferFrom(address(this), listing.seller, listing.tokenId);
        } else if (listing.tokenType == TokenType.ERC1155) {
            IERC1155(listing.nftAddress).safeTransferFrom(
                address(this),
                listing.seller,
                listing.tokenId,
                listing.quantity,
                ""
            );
        }

        delete listings[listingId];
        emit ListingCancelled(listingId);
    }

    function purchase(uint256 listingId, uint256 quantity) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.seller == address(0)) revert ListingDoesNotExist();

        uint256 purchaseQuantity;
        if (listing.tokenType == TokenType.ERC721) {
            if (quantity != 1) revert InvalidQuantity();
            purchaseQuantity = 1;
        } else if (listing.tokenType == TokenType.ERC1155) {
            if (quantity == 0 || quantity > listing.quantity) revert InvalidQuantity();
            purchaseQuantity = quantity;
        } else {
            revert UnsupportedTokenType();
        }

        uint256 totalPrice = listing.price * purchaseQuantity;
        if (msg.value < totalPrice) revert InsufficientPayment();

        uint256 protocolFee = (totalPrice * protocolFeeRate) / 1 ether;
        uint256 sellerAmount = totalPrice - protocolFee;

        protocolFeeRecipient.sendValue(protocolFee);
        payable(listing.seller).sendValue(sellerAmount);

        if (listing.tokenType == TokenType.ERC721) {
            IERC721(listing.nftAddress).safeTransferFrom(address(this), msg.sender, listing.tokenId);
            delete listings[listingId];
        } else {
            IERC1155(listing.nftAddress).safeTransferFrom(
                address(this),
                msg.sender,
                listing.tokenId,
                purchaseQuantity,
                ""
            );
            if (listing.quantity == purchaseQuantity) {
                delete listings[listingId];
            } else {
                listing.quantity -= purchaseQuantity;
            }
        }

        // Refund excess ETH (if any)
        if (msg.value > totalPrice) {
            payable(msg.sender).sendValue(msg.value - totalPrice);
        }

        emit ItemSold(listingId, msg.sender, purchaseQuantity, totalPrice);
    }

    // ---------------------------------------------------------------------
    // ERC165 support
    // ---------------------------------------------------------------------
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155HolderUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
