// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// This is the minimal and simplest implementation as a mock for USDC
/// For more real behavior, choose to write fork test
contract MockUsdc is ERC20 {
    constructor() ERC20("USDC", "USDC") {
        _mint(msg.sender, 1e6 * 1e6); // 1M USDC
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
