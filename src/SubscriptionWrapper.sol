// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC1155} from "@openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";
import {WrappedSubscription} from "./WrappedSubscription.sol";

contract SubscriptionWrapper is IERC1155Receiver {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IERC1155 private immutable i_subscriptionNft;
    mapping(uint256 planId => WrappedSubscription wrappedToken)
        private s_planIdToWrappedToken;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SubscriptionWrapper__TokenNotWrapped(uint256 planId);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event WrappedTokenCreated(
        uint256 indexed planId,
        address indexed wrappedToken
    );

    event Deposited(
        address indexed user,
        uint256 indexed tokenId,
        uint256 amount
    );

    event Withdrawn(
        address indexed user,
        uint256 indexed tokenId,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _subscriptionNft) {
        i_subscriptionNft = IERC1155(_subscriptionNft);
    }

    /*//////////////////////////////////////////////////////////////
                     EXTERNAL AND PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function ensureWrappedToken(
        uint256 planId
    ) public returns (WrappedSubscription) {
        if (address(s_planIdToWrappedToken[planId]) == address(0)) {
            WrappedSubscription newToken = new WrappedSubscription(planId);
            s_planIdToWrappedToken[planId] = newToken;
            emit WrappedTokenCreated(planId, address(newToken));
        }
        return s_planIdToWrappedToken[planId];
    }

    function deposit(uint256 planId, uint256 tokenId, uint256 amount) external {
        WrappedSubscription wrapped = ensureWrappedToken(planId);

        // Transfer ERC-1155 from user to contract
        i_subscriptionNft.safeTransferFrom(
            msg.sender,
            address(this),
            tokenId,
            amount,
            ""
        );

        // Mint ERC-20 equivalent
        wrapped.mint(msg.sender, amount, tokenId);

        emit Deposited(msg.sender, tokenId, amount);
    }

    function withdraw(
        uint256 planId,
        uint256 tokenId,
        uint256 amount
    ) external {
        WrappedSubscription wrapped = s_planIdToWrappedToken[planId];

        if (address(wrapped) == address(0)) {
            revert SubscriptionWrapper__TokenNotWrapped(planId);
        }

        // Burn ERC-20 from user
        wrapped.burn(msg.sender, amount, tokenId);

        // Transfer ERC-1155 back to user
        i_subscriptionNft.safeTransferFrom(
            address(this),
            msg.sender,
            tokenId,
            amount,
            ""
        );

        emit Withdrawn(msg.sender, tokenId, amount);
    }

    /*//////////////////////////////////////////////////////////////
                           REQUIRED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getWrappedToken(
        uint256 planId
    ) external view returns (WrappedSubscription) {
        return s_planIdToWrappedToken[planId];
    }
}
