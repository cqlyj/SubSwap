// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract WrappedSubscription is ERC20, Ownable {
    using Strings for uint256;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private s_planID;
    mapping(address owner => uint256[] tokenIds) private s_ownerToTokenIds;
    mapping(address owner => mapping(uint256 tokenId => uint256 amount))
        private s_ownerToTokenIdToAmount;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error WrappedSubscription__InsufficientBalance(
        address owner,
        uint256 tokenId
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        uint256 _planId
    )
        ERC20(
            string(
                abi.encodePacked("Wrapped Subscription ", _planId.toString())
            ),
            string(abi.encodePacked("wSub_", _planId.toString()))
        )
        Ownable(msg.sender)
    {
        s_planID = _planId;
    }

    /*//////////////////////////////////////////////////////////////
                     EXTERNAL AND PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function mint(
        address to,
        uint256 amount,
        uint256 tokenId
    ) external onlyOwner {
        s_ownerToTokenIds[to].push(tokenId);
        s_ownerToTokenIdToAmount[to][tokenId] = amount;
        _mint(to, amount);
    }

    function burn(
        address from,
        uint256 amount,
        uint256 tokenId
    ) external onlyOwner {
        if (s_ownerToTokenIdToAmount[from][tokenId] < amount) {
            revert WrappedSubscription__InsufficientBalance(from, tokenId);
        }
        s_ownerToTokenIdToAmount[from][tokenId] -= amount;
        _burn(from, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getPlanId() external view returns (uint256) {
        return s_planID;
    }

    function getTokenIds(
        address owner
    ) external view returns (uint256[] memory) {
        return s_ownerToTokenIds[owner];
    }

    function getTokenAmount(
        address owner,
        uint256 tokenId
    ) external view returns (uint256) {
        return s_ownerToTokenIdToAmount[owner][tokenId];
    }
}
