// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IYieldVault is IERC4626 {
    function compound() external returns (uint256 harvested);
    function emergencyWithdraw() external returns (uint256 recovered);

    function forgeVault() external view returns (address);
    function trancheId() external view returns (uint8);
    function totalInvested() external view returns (uint256);
    function totalHarvested() external view returns (uint256);
    function lastCompoundTime() external view returns (uint256);
    function compoundInterval() external view returns (uint256);

    function getMetrics()
        external
        view
        returns (
            uint256 totalAssets_,
            uint256 totalInvested_,
            uint256 totalHarvested_,
            uint256 sharePrice,
            uint256 apy
        );

    event Compounded(uint256 yieldClaimed, uint256 reinvested, address caller);
    event EmergencyWithdrawExecuted(uint256 amountRecovered);

    // --- Pausable ---
    function pause() external;
    function unpause() external;
}
