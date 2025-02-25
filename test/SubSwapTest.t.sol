// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {SubscriptionFactory} from "src/SubscriptionFactory.sol";
import {SubscriptionNft} from "src/SubscriptionNFT.sol";
import {SubscriptionWrapper} from "src/SubscriptionWrapper.sol";
import {SubscriptionMarketplace} from "src/SubscriptionMarketplace.sol";
import {SubscriptionPricingHook} from "src/SubscriptionPricingHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {MockUsdc} from "test/mocks/MockUsdc.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolKey, PoolIdLibrary} from "v4-core/src/types/PoolKey.sol";

/// This is fork test for sepolia
/// Please run `make test-sepolia`

contract SubSwapTest is Test {
    using CurrencyLibrary for Currency;

    SubscriptionFactory public factory;
    SubscriptionNft public subscriptionNft;
    address public contentCreator = makeAddr("content creator");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    SubscriptionWrapper public wrapper;
    SubscriptionPricingHook public pricingHook;
    SubscriptionMarketplace public marketplace;
    MockUsdc public usdc;
    IAllowanceTransfer private immutable permit2 =
        IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    PositionManager private immutable positionManager =
        PositionManager(payable(0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4));

    function setUp() external {
        factory = new SubscriptionFactory();
        subscriptionNft = new SubscriptionNft(address(factory));
        wrapper = new SubscriptionWrapper(address(subscriptionNft));

        // error HookAddressNotValid for now, come back fix this soon
        // pricingHook = new SubscriptionPricingHook(
        //     IPoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543), // PoolManager
        //     address(subscriptionNft)
        // );

        vm.startPrank(user1);
        usdc = new MockUsdc();
        marketplace = new SubscriptionMarketplace(
            0xE03A1074c86CFeDd5C142C4F04F1a1536e203543, // PoolManager
            address(usdc), // USDC
            // address(pricingHook), // _defaultHooks
            address(0),
            address(positionManager), // _positionManager
            address(permit2), // _permit2
            0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b // _router
        );
        vm.stopPrank();

        usdc.mint(user2, 1e6 * 1e6);
    }

    // Not a good practice to write a huge test, but this will show the overall process of the subscription
    // And many magic numbers here, replace them with constants makes the code more readable
    function testEveryThingWorksFine() external {
        // create a plan
        vm.prank(contentCreator);
        factory.createPlan("Plan1", "Plan1 description", 30 days, 1e6, true); // 1 USDC

        // create a subscription
        // vm.expectRevert(
        //     SubscriptionNft.SubscriptionNFT__InvalidPlanId.selector
        // );
        // subscriptionNft.createSubscription(1, 10000); // planId 1, 10000 tokens

        vm.prank(user1);
        subscriptionNft.createSubscription(0, 10000); // planId 0, 10000 tokens
        vm.prank(user2);
        subscriptionNft.createSubscription(0, 10000); // planId 0, 10000 tokens

        // wrap the subscription
        vm.startPrank(user1);
        subscriptionNft.setApprovalForAll(address(wrapper), true);
        wrapper.deposit(0, 1, 5000); // planId, tokenId, amount
        // wrapper.withdraw(1, 5000); // tokenId, amount
        vm.stopPrank();

        vm.startPrank(user2);
        subscriptionNft.setApprovalForAll(address(wrapper), true);
        // Since the time we create the subscription is different, the tokenId will be different
        wrapper.deposit(0, 2, 5000); // planId, tokenId, amount
        vm.stopPrank();

        // create the pool
        bytes memory hookData = abi.encode(1);
        address wrapperTokenAddress = address(wrapper.getWrappedToken(0)); // get the token based on planId

        vm.startPrank(user1);

        // Approve the token pairs for the pool
        _tokenApprovals(IERC20(wrapperTokenAddress), IERC20(address(usdc)));

        bytes[] memory params = marketplace.generateCreatePoolParams(
            wrapperTokenAddress, // wrappedToken
            3000, // lpFee
            IHooks(address(0)), // hooks
            79228162514264337593543950336, // startingPrice
            -600, // tickLower
            600, // tickUpper
            500, // amount0Desired
            500, // amount1Desired
            501, // amount0Max
            501, // amount1Max
            hookData
        );

        // After this call, the pool will be created and the tokens will be deposited
        positionManager.multicall(params);

        vm.stopPrank();

        // Another user tries to mint a new position in this pool
        PoolKey memory poolKey = marketplace.getPoolKey(
            wrapperTokenAddress,
            3000, // swapFee
            IHooks(address(0)) // no hooks for now
        );

        vm.startPrank(user2);

        _tokenApprovals(IERC20(wrapperTokenAddress), IERC20(address(usdc)));

        (
            bytes memory mintParams,
            uint256 deadline,
            uint256 valueToPass,
            uint256 user2TokenId
        ) = marketplace.generateMintPositionParams(
                poolKey,
                -600,
                600,
                marketplace.getPoolLiquidity(poolKey),
                501,
                501,
                user2,
                hookData
            );

        positionManager.modifyLiquidities{value: valueToPass}(
            mintParams,
            deadline
        );

        vm.stopPrank();

        console.log(
            "The new minted position have the tokenId %s",
            user2TokenId
        );

        // Let user2 increaseLiquidity!

        vm.startPrank(user2);

        (bytes memory increaseParams, uint256 increaseDeadline) = marketplace
            .generateIncreaseLiquidityParams(
                wrapperTokenAddress,
                user2TokenId,
                2000, // liquidityIncrease,
                2001, // Maximum amount of token0 to spend
                2001, // Maximum amount of token1 to spend
                false // useFeesAsLiquidity Whether to use accumulated fees
            );

        positionManager.modifyLiquidities(increaseParams, increaseDeadline);

        vm.stopPrank();

        // decrease liquidity back to original
        vm.startPrank(user2);

        (bytes memory decreaseParams, uint256 decreaseDeadline) = marketplace
            .generateDecreaseLiquidityParams(
                wrapperTokenAddress,
                user2TokenId,
                2000, // liquidityDecrease,
                59, // amount0Min
                59, // amount1Min
                user2 // recipient
            );

        positionManager.modifyLiquidities(decreaseParams, decreaseDeadline);

        vm.stopPrank();

        // Let user2 collect the fees
        vm.startPrank(user2);

        (
            bytes memory collectFeesParams,
            uint256 collectFeeDeadline
        ) = marketplace.generateCollectFeesParams(
                wrapperTokenAddress,
                user2TokenId,
                user2
            );

        positionManager.modifyLiquidities(
            collectFeesParams,
            collectFeeDeadline
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _tokenApprovals(IERC20 token0, IERC20 token1) internal {
        token0.approve(address(permit2), type(uint256).max);
        permit2.approve(
            address(token0),
            address(positionManager),
            type(uint160).max,
            type(uint48).max
        );
        token1.approve(address(permit2), type(uint256).max);
        permit2.approve(
            address(token1),
            address(positionManager),
            type(uint160).max,
            type(uint48).max
        );
    }
}
