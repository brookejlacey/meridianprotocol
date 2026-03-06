// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITrancheToken is IERC20 {
    // --- Events ---
    event ShareTransferHook(address indexed from, address indexed to, uint256 amount);

    // --- Functions ---
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function vault() external view returns (address);
    function trancheId() external view returns (uint8);
}
