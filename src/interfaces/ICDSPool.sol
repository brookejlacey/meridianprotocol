// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface ICDSPool {
    enum PoolStatus {
        Active,
        Triggered,
        Settled,
        Expired
    }

    struct PoolTerms {
        address referenceAsset;     // ForgeVault being insured
        address collateralToken;    // Token for premiums and collateral (e.g., USDC)
        address oracle;             // CreditEventOracle
        uint256 maturity;           // Pool expiry timestamp
        uint256 baseSpreadWad;      // Base annual spread (WAD)
        uint256 slopeWad;           // Bonding curve slope (WAD)
    }

    struct ProtectionPosition {
        address buyer;
        uint256 notional;           // Protection amount
        uint256 premiumPaid;        // Total premium deposited
        uint256 spreadWad;          // Locked-in average spread (WAD)
        uint256 startTime;          // When protection was purchased
        bool active;                // Still active
    }

    // --- Events ---
    event LiquidityDeposited(address indexed lp, uint256 amount, uint256 shares);
    event LiquidityWithdrawn(address indexed lp, uint256 shares, uint256 amount);
    event ProtectionBought(address indexed buyer, uint256 indexed positionId, uint256 notional, uint256 premium, uint256 spreadWad);
    event ProtectionClosed(address indexed buyer, uint256 indexed positionId, uint256 refund);
    event PremiumsAccrued(uint256 totalAccrued, uint256 timestamp);
    event CreditEventTriggered(uint256 timestamp);
    event PoolSettled(uint256 totalPayout, uint256 recoveryRate);
    event PoolExpired(uint256 timestamp);
    event SettlementClaimed(address indexed buyer, uint256 amount);
    event ProtocolFeeCollected(uint256 amount);
    event ProtocolFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);

    // --- LP Functions ---
    function deposit(uint256 amount) external returns (uint256 shares);
    function withdraw(uint256 shares) external returns (uint256 amount);

    // --- Protection Buyer Functions ---
    function buyProtection(uint256 notional, uint256 maxPremium) external returns (uint256 positionId);
    function buyProtectionFor(uint256 notional, uint256 maxPremium, address beneficiary) external returns (uint256 positionId);
    function closeProtection(uint256 positionId) external returns (uint256 refund);

    // --- Lifecycle ---
    function accrueAllPremiums() external;
    function triggerCreditEvent() external;
    function settle(uint256 recoveryRateWad) external;
    function claimSettlement() external returns (uint256 amount);
    function expire() external;

    // --- View ---
    function currentSpread() external view returns (uint256);
    function quoteProtection(uint256 notional) external view returns (uint256 premium);
    function totalAssets() external view returns (uint256);
    function totalProtectionSold() external view returns (uint256);
    function utilizationRate() external view returns (uint256);
    function getPosition(uint256 positionId) external view returns (ProtectionPosition memory);
    function getPoolTerms() external view returns (PoolTerms memory);
    function getPoolStatus() external view returns (PoolStatus);
    function totalShares() external view returns (uint256);
    function sharesOf(address lp) external view returns (uint256);
    function activePositionCount() external view returns (uint256);
    function convertToAssets(uint256 shareAmount) external view returns (uint256);
    function convertToShares(uint256 amount) external view returns (uint256);

    // --- Protocol Fee ---
    function treasury() external view returns (address);
    function protocolFeeBps() external view returns (uint256);
    function totalProtocolFeesCollected() external view returns (uint256);
    function setProtocolFee(uint256 newFeeBps) external;

    // --- Pausable ---
    function pause() external;
    function unpause() external;
}
