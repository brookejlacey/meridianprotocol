// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockYieldSource
/// @notice ERC20 token that simulates a yield-bearing asset for testing.
/// @dev Has a `generateYield(address, uint256)` function to mint tokens
///      as if yield was accrued. In production, this would be the actual
///      underlying asset (e.g., USDC from loan repayments).
contract MockYieldSource is ERC20 {
    uint8 private immutable _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Mint tokens to any address (for testing)
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Simulate yield generation by minting to a recipient
    function generateYield(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    /// @notice Burn tokens (for testing)
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
