// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {MeridianMath} from "../libraries/MeridianMath.sol";

/// @title CollateralOracle
/// @notice Asset pricing and risk-weight registry for Nexus margin calculations.
/// @dev All prices are 18-decimal USD values. Risk weights are in basis points (10000 = 100%).
///
///      Default risk weights (from plan):
///        Senior tranche: 8500 (85%)
///        Mezzanine:      6000 (60%)
///        Equity:         4000 (40%)
///        AVAX:           7000 (70%)
///        Stablecoins:    9500 (95%)
///
///      Collateral value = amount * price * riskWeight / (1e18 * BPS)
contract CollateralOracle is Ownable2Step {
    using MeridianMath for uint256;

    // --- State ---

    /// @notice Asset price in USD (18 decimals). E.g., 1e18 = $1.00
    mapping(address asset => uint256 price) public prices;

    /// @notice Risk weight per asset in basis points. E.g., 9500 = 95%
    mapping(address asset => uint256 weight) public riskWeights;

    /// @notice Whether the asset has been registered
    mapping(address asset => bool registered) public isSupported;

    // --- Events ---
    event PriceUpdated(address indexed asset, uint256 price);
    event RiskWeightUpdated(address indexed asset, uint256 weight);
    event AssetRegistered(address indexed asset, uint256 price, uint256 riskWeight);

    constructor() Ownable(msg.sender) {}

    // --- Admin ---

    /// @notice Register a new collateral asset with price and risk weight
    function registerAsset(address asset, uint256 price_, uint256 riskWeight_) external onlyOwner {
        require(asset != address(0), "CollateralOracle: zero address");
        require(price_ > 0, "CollateralOracle: zero price");
        require(riskWeight_ <= MeridianMath.BPS, "CollateralOracle: weight > 100%");

        prices[asset] = price_;
        riskWeights[asset] = riskWeight_;
        isSupported[asset] = true;

        emit AssetRegistered(asset, price_, riskWeight_);
    }

    /// @notice Update price for a registered asset
    function setPrice(address asset, uint256 price_) external onlyOwner {
        require(isSupported[asset], "CollateralOracle: not registered");
        require(price_ > 0, "CollateralOracle: zero price");
        prices[asset] = price_;
        emit PriceUpdated(asset, price_);
    }

    /// @notice Update risk weight for a registered asset
    function setRiskWeight(address asset, uint256 riskWeight_) external onlyOwner {
        require(isSupported[asset], "CollateralOracle: not registered");
        require(riskWeight_ <= MeridianMath.BPS, "CollateralOracle: weight > 100%");
        riskWeights[asset] = riskWeight_;
        emit RiskWeightUpdated(asset, riskWeight_);
    }

    /// @notice Batch register assets
    function registerAssets(
        address[] calldata assets,
        uint256[] calldata prices_,
        uint256[] calldata riskWeights_
    ) external onlyOwner {
        require(
            assets.length == prices_.length && prices_.length == riskWeights_.length,
            "CollateralOracle: length mismatch"
        );
        for (uint256 i = 0; i < assets.length; i++) {
            require(assets[i] != address(0), "CollateralOracle: zero address");
            require(prices_[i] > 0, "CollateralOracle: zero price");
            require(riskWeights_[i] <= MeridianMath.BPS, "CollateralOracle: weight > 100%");

            prices[assets[i]] = prices_[i];
            riskWeights[assets[i]] = riskWeights_[i];
            isSupported[assets[i]] = true;

            emit AssetRegistered(assets[i], prices_[i], riskWeights_[i]);
        }
    }

    // --- View ---

    /// @notice Get the USD price of an asset
    function getPrice(address asset) external view returns (uint256) {
        require(isSupported[asset], "CollateralOracle: not registered");
        return prices[asset];
    }

    /// @notice Get the risk weight of an asset
    function getRiskWeight(address asset) external view returns (uint256) {
        require(isSupported[asset], "CollateralOracle: not registered");
        return riskWeights[asset];
    }

    /// @notice Get risk-adjusted collateral value in USD
    /// @param asset The collateral asset
    /// @param amount The raw token amount (18 decimals)
    /// @return value Risk-adjusted USD value (18 decimals)
    function getCollateralValue(address asset, uint256 amount) external view returns (uint256 value) {
        require(isSupported[asset], "CollateralOracle: not registered");
        // value = (amount * price / WAD) * riskWeight / BPS
        // Split into two steps to prevent triple-multiply overflow
        value = MeridianMath.bpsMul(MeridianMath.wadMul(amount, prices[asset]), riskWeights[asset]);
    }

    /// @notice Get raw (non-risk-adjusted) USD value
    /// @param asset The collateral asset
    /// @param amount The raw token amount (18 decimals)
    /// @return value USD value (18 decimals)
    function getRawValue(address asset, uint256 amount) external view returns (uint256 value) {
        require(isSupported[asset], "CollateralOracle: not registered");
        value = MeridianMath.wadMul(amount, prices[asset]);
    }
}
