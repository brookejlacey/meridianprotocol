// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface ICDSContract {
    enum CDSStatus {
        Active,
        Triggered,
        Settled,
        Expired
    }

    struct CDSTerms {
        address referenceAsset; // ForgeVault address
        uint256 protectionAmount; // notional
        uint256 premiumRate; // annual basis points
        uint256 maturity; // timestamp
        address collateralToken;
    }

    event ProtectionBought(address indexed buyer, uint256 amount, uint256 premiumRate);
    event ProtectionSold(address indexed seller, uint256 collateralPosted);
    event CreditEventTriggered(uint256 timestamp);
    event Settled(address indexed buyer, uint256 payoutAmount);
    event Expired(uint256 timestamp);

    function buyProtection(uint256 amount, uint256 maxPremium) external;
    function buyProtectionFor(uint256 amount, uint256 maxPremium, address beneficiary) external;
    function sellProtection(uint256 collateralAmount) external;
    function payPremium() external;
    function triggerCreditEvent() external;
    function settle() external;
    function expire() external;
    function getStatus() external view returns (CDSStatus);
    function getTerms() external view returns (CDSTerms memory);
}
