// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title SubscriptionFactory
/// @author Luo Yingjie
/// @notice Creates and manages different types of subscription plans

contract SubscriptionFactory {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private s_planId;
    mapping(uint256 planId => SubscriptionPlan plan) private s_plans;
    mapping(address creator => uint256[] planIds) private s_creatorPlanIds;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct SubscriptionPlan {
        uint256 planId;
        string name;
        string description;
        uint256 duration;
        uint256 price;
        address creator;
        bool isTransferable;
        bool isActive;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SubscriptionFactory__InvalidParams();
    error SubscriptionFactory__NotPlanCreator();
    error SubscriptionFactory__NotActivePlan();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PlanCreated(
        uint256 indexed planId,
        string name,
        uint256 duration,
        uint256 price,
        address indexed creator,
        bool isTransferable
    );

    event PlanModified(
        uint256 indexed planId,
        uint256 newPrice,
        uint256 newDuration
    );

    event PlanStateToggled(uint256 indexed planId, bool isActive);

    /*//////////////////////////////////////////////////////////////
                     EXTERNAL AND PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Creates new subscription plan templates
    // Returns unique plan ID
    function createPlan(
        string memory name,
        string memory description,
        uint256 duration,
        uint256 price,
        bool isTransferable
    ) external returns (uint256 planId) {
        if (duration <= 0 || price <= 0) {
            revert SubscriptionFactory__InvalidParams();
        }

        planId = s_planId;
        s_planId++;
        s_plans[planId] = SubscriptionPlan(
            planId,
            name,
            description,
            duration,
            price,
            msg.sender,
            isTransferable,
            true
        );
        s_creatorPlanIds[msg.sender].push(planId);

        emit PlanCreated(
            planId,
            name,
            duration,
            price,
            msg.sender,
            isTransferable
        );
    }

    // Updates existing plan parameters
    // Only callable by plan creator
    function modifyPlan(
        uint256 planId,
        uint256 newPrice,
        uint256 newDuration
    ) external {
        SubscriptionPlan storage plan = s_plans[planId];
        if (plan.creator != msg.sender) {
            revert SubscriptionFactory__NotPlanCreator();
        }
        if (!plan.isActive) {
            revert SubscriptionFactory__NotActivePlan();
        }
        if (newPrice <= 0 || newDuration <= 0) {
            revert SubscriptionFactory__InvalidParams();
        }

        plan.price = newPrice;
        plan.duration = newDuration;

        emit PlanModified(planId, newPrice, newDuration);
    }

    // Activates or deactivates a plan
    // Only callable by plan creator
    function togglePlan(uint256 planId) external {
        SubscriptionPlan storage plan = s_plans[planId];
        if (plan.creator != msg.sender) {
            revert SubscriptionFactory__NotPlanCreator();
        }

        plan.isActive = !plan.isActive;

        emit PlanStateToggled(planId, plan.isActive);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getPlan(
        uint256 planId
    ) external view returns (SubscriptionPlan memory) {
        return s_plans[planId];
    }

    function getCreatorPlanIds(
        address creator
    ) external view returns (uint256[] memory) {
        return s_creatorPlanIds[creator];
    }
}
