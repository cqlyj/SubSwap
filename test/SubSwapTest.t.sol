// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {SubscriptionFactory} from "src/SubscriptionFactory.sol";
import {SubscriptionNft} from "src/SubscriptionNFT.sol";
import {SubscriptionWrapper} from "src/SubscriptionWrapper.sol";

contract SubSwapTest is Test {
    SubscriptionFactory public factory;
    address public contentCreator = makeAddr("content creator");
    SubscriptionNft public subscriptionNft;
    address public user1 = makeAddr("user1");
    SubscriptionWrapper public wrapper;

    function setUp() external {
        factory = new SubscriptionFactory();
        subscriptionNft = new SubscriptionNft(address(factory));
        wrapper = new SubscriptionWrapper(address(subscriptionNft));
    }

    function testEveryThingWorksFine() external {
        // create a plan
        vm.prank(contentCreator);
        factory.createPlan("Plan1", "Plan1 description", 30 days, 1e6, true); // 1 USDC

        // create a subscription
        vm.expectRevert(
            SubscriptionNft.SubscriptionNFT__InvalidPlanId.selector
        );
        subscriptionNft.createSubscription(1, 1000); // planId 1, 1000 tokens

        vm.prank(user1);
        subscriptionNft.createSubscription(0, 1000); // planId 1, 1000 tokens

        // wrap the subscription
        vm.startPrank(user1);
        subscriptionNft.setApprovalForAll(address(wrapper), true);
        wrapper.deposit(1, 500); // tokenId, amount
        // wrapper.withdraw(1, 500); // tokenId, amount
        vm.stopPrank();
    }
}
