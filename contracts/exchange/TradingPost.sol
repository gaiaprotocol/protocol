// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract TradingPost is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    ERC1155HolderUpgradeable,
    UUPSUpgradeable
{
    using Address for address payable;

    address payable public protocolFeeRecipient;
    uint256 public protocolFeeRate;

    event ProtocolFeeRecipientUpdated(address indexed protocolFeeRecipient);
    event ProtocolFeeRateUpdated(uint256 rate);

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

    function initialize(address payable _protocolFeeRecipient, uint256 _protocolFeeRate) external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeRate = _protocolFeeRate;

        nextListingId = 1;

        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
        emit ProtocolFeeRateUpdated(_protocolFeeRate);
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

    function listItem(
        address nftAddress,
        uint256 tokenId,
        TokenType tokenType,
        uint256 quantity,
        uint256 price
    ) external nonReentrant {
        require(price > 0, "Price must be greater than zero");
        if (tokenType == TokenType.ERC721) {
            require(quantity == 1, "ERC721 quantity must be 1");
            IERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId);
        } else if (tokenType == TokenType.ERC1155) {
            require(quantity > 0, "Quantity must be greater than zero");
            IERC1155(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId, quantity, "");
        } else {
            revert("Unsupported token type");
        }

        uint256 listingId = nextListingId;
        nextListingId++;

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
        require(listing.seller != address(0), "Listing does not exist");
        require(msg.sender == listing.seller, "Only seller can cancel listing");

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
        require(listing.seller != address(0), "Listing does not exist");

        uint256 purchaseQuantity;
        if (listing.tokenType == TokenType.ERC721) {
            require(quantity == 1, "Quantity must be 1 for ERC721");
            purchaseQuantity = 1;
        } else if (listing.tokenType == TokenType.ERC1155) {
            require(quantity > 0 && quantity <= listing.quantity, "Invalid quantity");
            purchaseQuantity = quantity;
        } else {
            revert("Unsupported token type");
        }

        uint256 totalPrice = listing.price * purchaseQuantity;
        require(msg.value >= totalPrice, "Insufficient payment");

        uint256 protocolFee = (totalPrice * protocolFeeRate) / 1 ether;
        uint256 sellerAmount = totalPrice - protocolFee;

        protocolFeeRecipient.sendValue(protocolFee);
        payable(listing.seller).sendValue(sellerAmount);

        if (listing.tokenType == TokenType.ERC721) {
            IERC721(listing.nftAddress).safeTransferFrom(address(this), msg.sender, listing.tokenId);
            delete listings[listingId];
        } else if (listing.tokenType == TokenType.ERC1155) {
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

        if (msg.value > totalPrice) {
            payable(msg.sender).sendValue(msg.value - totalPrice);
        }

        emit ItemSold(listingId, msg.sender, purchaseQuantity, totalPrice);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC1155HolderUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
