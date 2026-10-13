// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Bankers In Control
/// @notice Fixed-supply ERC-20. The deploying account receives the entire supply once.
/// @dev No external mint, burn, administration, or upgrade mechanism is exposed.
contract BICToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev With factory deployment, msg.sender is the factory, not the transaction origin.
    constructor() ERC20("Bankers In Control", "BIC") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
