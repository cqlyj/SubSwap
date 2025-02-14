// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {SubscriptionFactory} from "./SubscriptionFactory.sol";

/// @title SubscriptionNft
/// @author Luo Yingjie
/// @notice This contract is used to create and manage subscription tokens

contract SubscriptionNft is ERC1155 {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private s_tokenId;
    SubscriptionFactory private immutable i_factory;
    mapping(uint256 tokenId => Subscription subscription)
        private s_tokenIdToSubscription;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Subscription {
        uint256 planId;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SubscriptionNFT__InvalidPlanId();
    error SubscriptionNFT__InvalidQuantity();
    error SubscriptionNFT__NotEnoughTokens();
    error SubscriptionNFT__NotActiveSubscription();
    error SubscriptionNFT__SubscriptionExpired();
    error SubscriptionNFT__NotTransferable();
    error SubscriptionNFT__NotSubscriptionOwner();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event SubscriptionCreated(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 quantity,
        uint256 indexed planId
    );

    event SubscriptionTransferred(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId,
        uint256 quantity
    );

    event SubscriptionExtended(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 additionalDuration
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _subscriptionFactory
    ) ERC1155("https://example.com/api/{id}.json") {
        i_factory = SubscriptionFactory(_subscriptionFactory);
        s_tokenId = 0;
    }

    /*//////////////////////////////////////////////////////////////
                     EXTERNAL AND PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Creates new subscription tokens
    // Parameters explain: planId is the ID of the subscription template, quantity is the number of tokens to mint
    // @TODO: We will update this function to make sure only when the content creator receives the payment, this function can be called
    function createSubscription(uint256 planId, uint256 quantity) external {
        if (!i_factory.getPlan(planId).isActive) {
            revert SubscriptionNFT__InvalidPlanId();
        }

        if (quantity <= 0) {
            revert SubscriptionNFT__InvalidQuantity();
        }

        s_tokenId++;
        uint256 duration = i_factory.getPlan(planId).duration;
        s_tokenIdToSubscription[s_tokenId] = Subscription({
            planId: planId,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            isActive: true
        });

        _mint(msg.sender, s_tokenId, quantity, "");

        emit SubscriptionCreated(msg.sender, s_tokenId, quantity, planId);
    }

    // Transfers subscription tokens between users
    // Checks if subscription is transferable and still valid
    function transferSubscription(
        address to,
        uint256 tokenId,
        uint256 amount
    ) external {
        if (balanceOf(msg.sender, tokenId) < amount) {
            revert SubscriptionNFT__NotEnoughTokens();
        }

        if (!s_tokenIdToSubscription[tokenId].isActive) {
            revert SubscriptionNFT__NotActiveSubscription();
        }

        if (block.timestamp > s_tokenIdToSubscription[tokenId].endTime) {
            s_tokenIdToSubscription[tokenId].isActive = false;
            revert SubscriptionNFT__SubscriptionExpired();
        }

        if (
            !i_factory
                .getPlan(s_tokenIdToSubscription[tokenId].planId)
                .isTransferable
        ) {
            revert SubscriptionNFT__NotTransferable();
        }

        _safeTransferFrom(msg.sender, to, tokenId, amount, "");

        emit SubscriptionTransferred(msg.sender, to, tokenId, amount);
    }

    // Extends the validity period of a subscription
    // Only callable by token owner or approved operator
    function extendSubscription(
        uint256 tokenId,
        uint256 additionalDuration
    ) external {
        if (balanceOf(msg.sender, tokenId) <= 0) {
            revert SubscriptionNFT__NotSubscriptionOwner();
        }

        // how the subscription get expired after the end time?
        if (!s_tokenIdToSubscription[tokenId].isActive) {
            revert SubscriptionNFT__NotActiveSubscription();
        }

        s_tokenIdToSubscription[tokenId].endTime += additionalDuration;

        emit SubscriptionExtended(msg.sender, tokenId, additionalDuration);
    }

    // Checks if a subscription is still valid and returns remaining time
    function checkValidity(
        uint256 tokenId
    ) external returns (bool isValid, uint256 remainingTime) {
        if (!s_tokenIdToSubscription[tokenId].isActive) {
            return (false, 0);
        }

        if (block.timestamp > s_tokenIdToSubscription[tokenId].endTime) {
            s_tokenIdToSubscription[tokenId].isActive = false;
            return (false, 0);
        }

        return (
            true,
            s_tokenIdToSubscription[tokenId].endTime - block.timestamp
        );
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getSubscription(
        uint256 tokenId
    ) external view returns (Subscription memory) {
        return s_tokenIdToSubscription[tokenId];
    }

    function getSubscriptionFactory() external view returns (address) {
        return address(i_factory);
    }

    function getTokenId() external view returns (uint256) {
        return s_tokenId;
    }
}
