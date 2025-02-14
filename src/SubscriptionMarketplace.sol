// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {PaymentProcessor} from "./PaymentProcessor.sol";

contract SubscriptionMarketplace is Ownable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IERC1155 private immutable i_subscriptionNft;
    PaymentProcessor private immutable i_paymentProcessor;
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

    error SubscriptionMarketplace__InvalidQuantity();
    error SubscriptionMarketplace__InvalidPrice();
    error SubscriptionMarketplace__NotEnoughBalance();
    error SubscriptionMarketplace__InvalidListingId();
    error SubscriptionMarketplace__NotOwner();
    error SubscriptionMarketplace__AlreadyCancelled();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

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
        address _paymentProcessor
    ) Ownable(msg.sender) {
        i_subscriptionNft = IERC1155(_subscriptionNft);
        i_paymentProcessor = PaymentProcessor(_paymentProcessor);
        s_listingId = 0;
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
        i_paymentProcessor.processPayment(
            msg.sender,
            listing.seller,
            totalPrice
        );

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

    function getListingId() external view returns (uint256) {
        return s_listingId;
    }

    function getSubscriptionNft() external view returns (address) {
        return address(i_subscriptionNft);
    }
}
