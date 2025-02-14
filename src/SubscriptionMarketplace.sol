// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SubscriptionMarketplace is Ownable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IERC1155 private immutable i_subscriptionNft;
    IERC20 private immutable i_usdc;
    uint256 private s_feePercentage = 3; // 3%
    uint256 private constant MAX_FEE_PERCENTAGE = 7; // 7%
    uint256 private constant FEE_PRECISION = 100;
    address private s_feeRecipient;
    uint256 private s_listingId;
    mapping(uint256 listingId => Listing listing) private s_listingIdToListing;

    /*//////////////////////////////////////////////////////////////
                                 STRUCT
    //////////////////////////////////////////////////////////////*/

    struct Listing {
        uint256 listingId;
        uint256 tokenId;
        address seller;
        uint256 price;
        uint256 quantity;
        bool isActive;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SubscriptionMarketplace__FeePercentageExceedsMax();
    error SubscriptionMarketplace__ZeroAddress();
    error SubscriptionMarketplace__InvalidQuantity();
    error SubscriptionMarketplace__InvalidPrice();
    error SubscriptionMarketplace__NotEnoughBalance();
    error SubscriptionMarketplace__InvalidListingId();
    error SubscriptionMarketplace__FailedToTransfer();
    error SubscriptionMarketplace__NotOwner();
    error SubscriptionMarketplace__AlreadyCancelled();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event FeePercentageUpdated(uint256 feePercentage);
    event FeeRecipientUpdated(address feeRecipient);
    event ListingCreated(
        uint256 indexed listingId,
        uint256 indexed tokenId,
        address indexed seller,
        uint256 price,
        uint256 quantity
    );
    event ListingSold(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 quantity
    );
    event ListingCanceled(uint256 indexed listingId);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _subscriptionNft,
        address _usdc,
        address _feeRecipient
    ) Ownable(msg.sender) {
        i_subscriptionNft = IERC1155(_subscriptionNft);
        i_usdc = IERC20(_usdc);
        s_feeRecipient = _feeRecipient;
        s_listingId = 0;
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        if (_feePercentage > MAX_FEE_PERCENTAGE) {
            revert SubscriptionMarketplace__FeePercentageExceedsMax();
        }

        s_feePercentage = _feePercentage;

        emit FeePercentageUpdated(_feePercentage);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) {
            revert SubscriptionMarketplace__ZeroAddress();
        }

        s_feeRecipient = _feeRecipient;

        emit FeeRecipientUpdated(_feeRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                     EXTERNAL AND PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function listSubscription(
        uint256 tokenId,
        uint256 price,
        uint256 quantity
    ) external {
        if (quantity == 0) {
            revert SubscriptionMarketplace__InvalidQuantity();
        }

        if (price == 0) {
            revert SubscriptionMarketplace__InvalidPrice();
        }

        if (i_subscriptionNft.balanceOf(msg.sender, tokenId) < quantity) {
            revert SubscriptionMarketplace__NotEnoughBalance();
        }

        s_listingId++;
        s_listingIdToListing[s_listingId] = Listing({
            listingId: s_listingId,
            tokenId: tokenId,
            seller: msg.sender,
            price: price,
            quantity: quantity,
            isActive: true
        });

        emit ListingCreated(s_listingId, tokenId, msg.sender, price, quantity);
    }

    function purchaseSubscription(
        uint256 listingId,
        uint256 quantity
    ) external {
        Listing storage listing = s_listingIdToListing[listingId];
        if (!listing.isActive) {
            revert SubscriptionMarketplace__InvalidListingId();
        }

        if (quantity > listing.quantity) {
            revert SubscriptionMarketplace__InvalidQuantity();
        }

        uint256 totalPrice = listing.price * quantity;
        uint256 fee = (totalPrice * s_feePercentage) / FEE_PRECISION;
        uint256 amountToSeller = totalPrice - fee;

        bool successTransferFee = i_usdc.transferFrom(
            msg.sender,
            s_feeRecipient,
            fee
        );
        bool successTransferSeller = i_usdc.transferFrom(
            msg.sender,
            listing.seller,
            amountToSeller
        );

        if (!successTransferFee || !successTransferSeller) {
            revert SubscriptionMarketplace__FailedToTransfer();
        }

        i_subscriptionNft.safeTransferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId,
            quantity,
            ""
        );

        listing.quantity -= quantity;
        if (listing.quantity == 0) {
            listing.isActive = false;
        }

        emit ListingSold(listingId, msg.sender, quantity);
    }

    function cancelListing(uint256 listingId) external {
        Listing storage listing = s_listingIdToListing[listingId];
        if (listing.seller != msg.sender) {
            revert SubscriptionMarketplace__NotOwner();
        }
        if (!listing.isActive) {
            revert SubscriptionMarketplace__AlreadyCancelled();
        }

        listing.isActive = false;

        emit ListingCanceled(listingId);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getListing(
        uint256 listingId
    ) external view returns (Listing memory) {
        return s_listingIdToListing[listingId];
    }

    function getFeePercentage() external view returns (uint256) {
        return s_feePercentage;
    }

    function getFeeRecipient() external view returns (address) {
        return s_feeRecipient;
    }

    function getListingId() external view returns (uint256) {
        return s_listingId;
    }

    function getSubscriptionNft() external view returns (address) {
        return address(i_subscriptionNft);
    }

    function getUsdc() external view returns (address) {
        return address(i_usdc);
    }
}
