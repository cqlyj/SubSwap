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
    mapping(uint256 tokenId => WrappedSubscription wrappedToken)
        private s_tokenIdToWrappedToken;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SubscriptionWrapper__TokenNotWrapped(uint256 tokenId);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event WrappedTokenCreated(
        uint256 indexed tokenId,
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
        uint256 tokenId
    ) public returns (WrappedSubscription) {
        if (address(s_tokenIdToWrappedToken[tokenId]) == address(0)) {
            WrappedSubscription newToken = new WrappedSubscription(tokenId);
            s_tokenIdToWrappedToken[tokenId] = newToken;
            emit WrappedTokenCreated(tokenId, address(newToken));
        }
        return s_tokenIdToWrappedToken[tokenId];
    }

    function deposit(uint256 tokenId, uint256 amount) external {
        WrappedSubscription wrapped = ensureWrappedToken(tokenId);

        // Transfer ERC-1155 from user to contract
        i_subscriptionNft.safeTransferFrom(
            msg.sender,
            address(this),
            tokenId,
            amount,
            ""
        );

        // Mint ERC-20 equivalent
        wrapped.mint(msg.sender, amount);

        emit Deposited(msg.sender, tokenId, amount);
    }

    function withdraw(uint256 tokenId, uint256 amount) external {
        WrappedSubscription wrapped = s_tokenIdToWrappedToken[tokenId];

        if (address(wrapped) == address(0)) {
            revert SubscriptionWrapper__TokenNotWrapped(tokenId);
        }

        // Burn ERC-20 from user
        wrapped.burn(msg.sender, amount);

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
}
