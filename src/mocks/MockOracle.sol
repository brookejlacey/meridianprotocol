// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockOracle
/// @notice Simple price oracle for testing. Returns admin-set prices.
/// @dev In production, replaced by Chainlink feeds or custom oracle aggregation.
contract MockOracle is Ownable {
    /// @notice Asset address => USD price (18 decimals)
    mapping(address => uint256) public prices;

    /// @notice Asset address => risk weight (0-10000, basis points)
    mapping(address => uint256) public riskWeights;

    /// @notice Whether the asset is supported
    mapping(address => bool) public isSupported;

    event PriceUpdated(address indexed asset, uint256 price);
    event RiskWeightUpdated(address indexed asset, uint256 weight);

    constructor() Ownable(msg.sender) {}

    /// @notice Set the price for an asset
    function setPrice(address asset, uint256 price) external onlyOwner {
        prices[asset] = price;
        isSupported[asset] = true;
        emit PriceUpdated(asset, price);
    }

    /// @notice Set the risk weight for an asset (basis points, max 10000)
    function setRiskWeight(address asset, uint256 weight) external onlyOwner {
        require(weight <= 10_000, "Weight > 100%");
        riskWeights[asset] = weight;
        emit RiskWeightUpdated(asset, weight);
    }

    /// @notice Get the price for an asset
    function getPrice(address asset) external view returns (uint256) {
        require(isSupported[asset], "Asset not supported");
        return prices[asset];
    }

    /// @notice Get the risk-adjusted value: amount * price * riskWeight / BPS
    function getRiskAdjustedValue(address asset, uint256 amount) external view returns (uint256) {
        require(isSupported[asset], "Asset not supported");
        return (amount * prices[asset] * riskWeights[asset]) / (1e18 * 10_000);
    }

    /// @notice Batch set prices
    function setPrices(address[] calldata assets, uint256[] calldata newPrices) external onlyOwner {
        require(assets.length == newPrices.length, "Length mismatch");
        for (uint256 i = 0; i < assets.length; i++) {
            prices[assets[i]] = newPrices[i];
            isSupported[assets[i]] = true;
            emit PriceUpdated(assets[i], newPrices[i]);
        }
    }
}
