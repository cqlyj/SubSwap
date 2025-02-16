// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ISubscriptionNft {
    struct Subscription {
        uint256 planId;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
    }

    error SubscriptionNFT__InvalidPlanId();
    error SubscriptionNFT__InvalidQuantity();
    error SubscriptionNFT__NotEnoughTokens();
    error SubscriptionNFT__NotActiveSubscription();
    error SubscriptionNFT__SubscriptionExpired();
    error SubscriptionNFT__NotTransferable();
    error SubscriptionNFT__NotSubscriptionOwner();

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

    function createSubscription(uint256 planId, uint256 quantity) external;

    function transferSubscription(
        address to,
        uint256 tokenId,
        uint256 amount
    ) external;

    function extendSubscription(
        uint256 tokenId,
        uint256 additionalDuration
    ) external;

    function checkValidity(
        uint256 tokenId
    ) external returns (bool isValid, uint256 remainingTime);

    function getSubscription(
        uint256 tokenId
    ) external view returns (Subscription memory);

    function getSubscriptionFactory() external view returns (address);

    function getTokenId() external view returns (uint256);
}
