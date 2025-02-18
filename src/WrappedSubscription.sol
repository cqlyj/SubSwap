// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract WrappedSubscription is ERC20, Ownable {
    using Strings for uint256;

    uint256 private s_tokenID;

    constructor(
        uint256 _tokenID
    )
        ERC20(
            string(
                abi.encodePacked("Wrapped Subscription ", _tokenID.toString())
            ),
            string(abi.encodePacked("wSub_", _tokenID.toString()))
        )
        Ownable(msg.sender)
    {
        s_tokenID = _tokenID;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function tokenId() external view returns (uint256) {
        return s_tokenID;
    }
}
