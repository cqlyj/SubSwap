// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/base/BaseHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {ISubscriptionNft} from "./interfaces/ISubscriptionNft.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract SubscriptionPricingHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using SafeCast for int256;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    mapping(PoolId poolId => SubscriptionData subscriptionData)
        private s_poolIdToSubscriptionData;
    ISubscriptionNft private immutable i_subscriptionNft;
    int256 private constant PRECISION = 1e18;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct SubscriptionData {
        uint256 basePrice;
        address nftContract;
        uint256 planId;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SubscriptionPricingHook__SubscriptionNotFound();
    error SubscriptionPricingHook__NoMatchingNFTFound();
    error SubscriptionPricingHook__NoTokenIdSpecified();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PriceUpdated(
        PoolId indexed poolId,
        uint256 indexed tokenId,
        uint256 newPrice
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IPoolManager _poolManager,
        address _subscriptionNft
    ) BaseHook(_poolManager) {
        i_subscriptionNft = ISubscriptionNft(_subscriptionNft);
    }

    /*//////////////////////////////////////////////////////////////
                           UNISWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /// @notice The hook called before a swap
    /// @param sender The initial msg.sender for the swap call
    /// @param key The key for the pool
    /// @param params The parameters for the swap
    /// @param hookData Arbitrary data handed into the PoolManager by the swapper to be passed on to the hook
    /// @return bytes4 The function selector for the hook
    /// @return BeforeSwapDelta The hook's delta in specified and unspecified currencies. Positive: the hook is owed/took currency, negative: the hook owes/sent currency
    /// @return uint24 Optionally override the lp fee, only used if three conditions are met: 1. the Pool has a dynamic fee, 2. the value's 2nd highest bit is set (23rd bit, 0x400000), and 3. the value is less than or equal to the maximum fee (1 million)

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();
        uint256 tokenId;

        if (params.amountSpecified > 0) {
            // positive => exactOut => swap NFT for USDC => sell NFT
            if (hookData.length > 0) {
                tokenId = abi.decode(hookData, (uint256));
            } else {
                revert SubscriptionPricingHook__NoTokenIdSpecified();
            }
        } else {
            // negative => exactIn => swap USDC for NFT => buy NFT
            if (hookData.length > 0) {
                // Decode user-specified tokenId
                tokenId = abi.decode(hookData, (uint256));
            } else {
                // Default: Find the best match
                tokenId = findMatchedNft(
                    poolId,
                    i_subscriptionNft.getSubscription(tokenId).planId,
                    params.amountSpecified
                );
            }
        }

        uint256 currentPrice = getPrice(tokenId, poolId);
        emit PriceUpdated(poolId, tokenId, currentPrice);

        // Adjust swap output based on dynamic pricing
        // params.amountSpecified => amount of Subscription NFTs to swap(most times 1)
        // adjustedAmount => amount of USDC to swap

        // The desired input amount if negative (exactIn), or the desired output amount if positive (exactOut)
        // int256 amountSpecified;

        // @audit this precision may cause the amount to be rounded down to 0
        int256 adjustedAmount = (params.amountSpecified *
            int256(currentPrice)) / PRECISION;

        if (params.amountSpecified > 0) {
            // positive => exactOut => swap NFT for USDC
            return (
                BaseHook.beforeSwap.selector,
                toBeforeSwapDelta(0, adjustedAmount.toInt128()),
                0
            );
        } else {
            // negative => exactIn => swap USDC for NFT
            // The user specifies the amount of USDC they want to pay.
            // The hook must determine which NFT they can get based on that payment.
            // The SFT is unique (not fungible like ERC-20s), so the hook must find the appropriate tokenId with a price matching the input USDC.
            return (
                BaseHook.beforeSwap.selector,
                toBeforeSwapDelta(adjustedAmount.toInt128(), 0),
                0
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTION
    //////////////////////////////////////////////////////////////*/

    function getPrice(
        uint256 tokenId,
        PoolId poolId
    ) public view returns (uint256 price) {
        SubscriptionData memory subscriptionData = s_poolIdToSubscriptionData[
            poolId
        ];

        if (subscriptionData.nftContract == address(0)) {
            revert SubscriptionPricingHook__SubscriptionNotFound();
        }

        // Since each SFT has a unique expiration, the price should be fetched based on the exact token ID rather than using a general poolId.
        // This tokenId should be an array with different tokenIds since the same id will be the same price.
        // We need to pass the exact tokenId we want to swap for.

        ISubscriptionNft.Subscription memory subscription = i_subscriptionNft
            .getSubscription(tokenId);

        if (
            subscriptionData.planId !=
            i_subscriptionNft.getSubscription(tokenId).planId
        ) {
            revert SubscriptionPricingHook__SubscriptionNotFound();
        }

        uint256 timeRemaining = subscription.endTime > block.timestamp
            ? subscription.endTime - block.timestamp
            : 0;
        uint256 duration = subscription.endTime - subscription.startTime;
        price = (subscriptionData.basePrice * timeRemaining) / duration;
    }

    // Creates a BeforeSwapDelta from specified and unspecified
    function toBeforeSwapDelta(
        int128 deltaSpecified,
        int128 deltaUnspecified
    ) public pure returns (BeforeSwapDelta beforeSwapDelta) {
        assembly ("memory-safe") {
            beforeSwapDelta := or(
                shl(128, deltaSpecified),
                and(sub(shl(128, 1), 1), deltaUnspecified)
            )
        }
    }

    // @update this function should be optimized to avoid iterating over all tokenIds
    function findMatchedNft(
        PoolId poolId,
        uint256 planId,
        int256 usdcAmount
    ) internal view returns (uint256 tokenId) {
        SubscriptionData memory subscriptionData = s_poolIdToSubscriptionData[
            poolId
        ];
        uint256[] memory tokenIds = i_subscriptionNft.getTokenIdsByPlanId(
            planId
        );

        if (tokenIds.length == 0) {
            revert SubscriptionPricingHook__NoMatchingNFTFound();
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            ISubscriptionNft.Subscription
                memory subscription = i_subscriptionNft.getSubscription(
                    tokenIds[i]
                );
            uint256 timeRemaining = subscription.endTime > block.timestamp
                ? subscription.endTime - block.timestamp
                : 0;
            uint256 duration = subscription.endTime - subscription.startTime;
            uint256 calculatedPrice = (subscriptionData.basePrice *
                timeRemaining) / duration;

            if (calculatedPrice <= uint256(usdcAmount)) {
                return tokenIds[i];
            }
        }
        revert SubscriptionPricingHook__NoMatchingNFTFound();
    }
}
