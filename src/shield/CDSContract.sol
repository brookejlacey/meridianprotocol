// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ICDSContract} from "../interfaces/ICDSContract.sol";
import {ICreditEventOracle} from "../interfaces/ICreditEventOracle.sol";
import {PremiumEngine} from "./PremiumEngine.sol";
import {MeridianMath} from "../libraries/MeridianMath.sol";

/// @title CDSContract
/// @notice A single credit default swap contract.
/// @dev Lifecycle: Pending → Active → Triggered/Expired → Settled
///
///      Buyer: pays periodic premiums, receives collateral payout on credit event.
///      Seller: posts collateral, earns premiums, loses collateral on credit event.
///
///      MVP simplifications:
///      - Single buyer, single seller per contract
///      - Full collateralization required (collateral >= notional)
///      - Premium payments in underlying token (plaintext for MVP)
///      - Settlement is full payout (no recovery rate calculation)
contract CDSContract is ICDSContract, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using MeridianMath for uint256;

    // --- State ---
    CDSStatus public status;
    CDSTerms public terms;

    address public buyer;
    address public seller;

    /// @notice Collateral posted by seller
    uint256 public collateralPosted;

    /// @notice Premium tracking
    PremiumEngine.PremiumState public premiumState;

    /// @notice Payment interval for premiums (e.g., 30 days)
    uint256 public paymentInterval;

    /// @notice Buyer's premium deposit (upfront escrow)
    uint256 public buyerPremiumDeposit;

    /// @notice Credit event oracle
    ICreditEventOracle public oracle;

    /// @notice Collateral token
    IERC20 public collateralToken;

    /// @notice Factory that created this contract
    address public factory;

    // --- Events ---
    event PremiumPaid(address indexed buyer, uint256 amount, uint256 timestamp);

    // --- Modifiers ---
    modifier onlyBuyer() {
        require(msg.sender == buyer, "CDSContract: not buyer");
        _;
    }

    modifier onlySeller() {
        require(msg.sender == seller, "CDSContract: not seller");
        _;
    }

    modifier inStatus(CDSStatus expected) {
        require(status == expected, "CDSContract: wrong status");
        _;
    }

    constructor(
        CDSTerms memory terms_,
        address oracle_,
        uint256 paymentInterval_,
        address factory_
    ) {
        require(terms_.referenceAsset != address(0), "CDSContract: zero ref asset");
        require(terms_.protectionAmount > 0, "CDSContract: zero notional");
        require(terms_.premiumRate > 0, "CDSContract: zero premium");
        require(terms_.maturity > block.timestamp, "CDSContract: maturity passed");
        require(terms_.collateralToken != address(0), "CDSContract: zero collateral token");
        require(oracle_ != address(0), "CDSContract: zero oracle");

        terms = terms_;
        oracle = ICreditEventOracle(oracle_);
        collateralToken = IERC20(terms_.collateralToken);
        paymentInterval = paymentInterval_;
        factory = factory_;
        status = CDSStatus.Active; // Start as active (pending is implicit before buyer/seller)
    }

    // --- Buyer Functions ---

    /// @notice Buy protection — deposit premium upfront and lock position
    /// @param amount Protection notional (must match terms)
    /// @param maxPremium Maximum premium buyer is willing to pay (slippage protection)
    function buyProtection(uint256 amount, uint256 maxPremium)
        external
        override
        nonReentrant
    {
        require(buyer == address(0), "CDSContract: buyer already set");
        require(amount == terms.protectionAmount, "CDSContract: amount mismatch");
        require(status == CDSStatus.Active, "CDSContract: not active");

        // Calculate required upfront deposit (1 payment period)
        uint256 durationDays = (terms.maturity - block.timestamp) / 1 days;
        require(durationDays > 0, "CDSContract: too close to maturity");
        uint256 totalPremium = PremiumEngine.calculateTotalPremium(
            terms.protectionAmount, terms.premiumRate, durationDays
        );
        require(totalPremium <= maxPremium, "CDSContract: premium exceeds max");

        // Require full premium upfront for MVP simplicity
        uint256 deposit = totalPremium;
        collateralToken.safeTransferFrom(msg.sender, address(this), deposit);

        buyer = msg.sender;
        buyerPremiumDeposit = deposit;

        premiumState = PremiumEngine.PremiumState({
            notional: terms.protectionAmount,
            annualSpreadBps: terms.premiumRate,
            startTime: block.timestamp,
            maturity: terms.maturity,
            lastPaymentTime: block.timestamp,
            totalPaid: 0
        });

        emit ProtectionBought(msg.sender, amount, terms.premiumRate);
    }

    /// @notice Buy protection on behalf of a beneficiary (for router/composability)
    /// @param amount Protection notional (must match terms)
    /// @param maxPremium Maximum premium willing to pay (slippage protection)
    /// @param beneficiary Address that becomes the buyer and receives settlements
    function buyProtectionFor(uint256 amount, uint256 maxPremium, address beneficiary)
        external
        override
        nonReentrant
    {
        require(buyer == address(0), "CDSContract: buyer already set");
        require(beneficiary != address(0), "CDSContract: zero beneficiary");
        require(amount == terms.protectionAmount, "CDSContract: amount mismatch");
        require(status == CDSStatus.Active, "CDSContract: not active");

        uint256 durationDays = (terms.maturity - block.timestamp) / 1 days;
        require(durationDays > 0, "CDSContract: too close to maturity");
        uint256 totalPremium = PremiumEngine.calculateTotalPremium(
            terms.protectionAmount, terms.premiumRate, durationDays
        );
        require(totalPremium <= maxPremium, "CDSContract: premium exceeds max");

        uint256 deposit = totalPremium;
        collateralToken.safeTransferFrom(msg.sender, address(this), deposit);

        buyer = beneficiary;
        buyerPremiumDeposit = deposit;

        premiumState = PremiumEngine.PremiumState({
            notional: terms.protectionAmount,
            annualSpreadBps: terms.premiumRate,
            startTime: block.timestamp,
            maturity: terms.maturity,
            lastPaymentTime: block.timestamp,
            totalPaid: 0
        });

        emit ProtectionBought(beneficiary, amount, terms.premiumRate);
    }

    /// @notice Sell protection — post collateral
    /// @param collateralAmount Amount of collateral to post (must >= notional)
    function sellProtection(uint256 collateralAmount)
        external
        override
        nonReentrant
    {
        require(seller == address(0), "CDSContract: seller already set");
        require(collateralAmount >= terms.protectionAmount, "CDSContract: insufficient collateral");
        require(status == CDSStatus.Active, "CDSContract: not active");
        require(block.timestamp < terms.maturity, "CDSContract: matured");

        collateralToken.safeTransferFrom(msg.sender, address(this), collateralAmount);
        seller = msg.sender;
        collateralPosted = collateralAmount;

        emit ProtectionSold(msg.sender, collateralAmount);
    }

    /// @notice Process accrued premium payment from buyer deposit to seller
    /// @dev Anyone can call this to stream premiums to the seller
    function payPremium() external override nonReentrant {
        require(buyer != address(0) && seller != address(0), "CDSContract: incomplete");
        require(status == CDSStatus.Active, "CDSContract: not active");

        uint256 accrued = PremiumEngine.accruedPremium(premiumState, block.timestamp);
        require(accrued > 0, "CDSContract: no premium due");
        require(accrued <= buyerPremiumDeposit, "CDSContract: deposit exhausted");

        buyerPremiumDeposit -= accrued;
        premiumState.lastPaymentTime = block.timestamp;
        premiumState.totalPaid += accrued;

        // Transfer premium to seller
        collateralToken.safeTransfer(seller, accrued);

        emit PremiumPaid(buyer, accrued, block.timestamp);
    }

    /// @notice Trigger a credit event — oracle-gated
    function triggerCreditEvent() external override nonReentrant {
        require(status == CDSStatus.Active, "CDSContract: not active");
        require(buyer != address(0) && seller != address(0), "CDSContract: incomplete");

        // Verify credit event via oracle
        require(
            oracle.hasActiveEvent(terms.referenceAsset),
            "CDSContract: no credit event"
        );

        status = CDSStatus.Triggered;
        emit CreditEventTriggered(block.timestamp);
    }

    /// @notice Settle after credit event — collateral to buyer
    function settle() external override nonReentrant {
        require(status == CDSStatus.Triggered, "CDSContract: not triggered");

        status = CDSStatus.Settled;

        // Pay any remaining accrued premium to seller first
        uint256 accrued = PremiumEngine.accruedPremium(premiumState, block.timestamp);
        uint256 premiumPayment = accrued.min(buyerPremiumDeposit);
        if (premiumPayment > 0) {
            buyerPremiumDeposit -= premiumPayment;
            premiumState.totalPaid += premiumPayment;
            collateralToken.safeTransfer(seller, premiumPayment);
        }

        // Transfer collateral to buyer (full payout for MVP)
        uint256 payout = collateralPosted.min(terms.protectionAmount);
        collateralPosted -= payout;
        collateralToken.safeTransfer(buyer, payout);

        // Return any excess collateral to seller
        if (collateralPosted > 0) {
            uint256 excess = collateralPosted;
            collateralPosted = 0;
            collateralToken.safeTransfer(seller, excess);
        }

        // Return unused premium deposit to buyer
        if (buyerPremiumDeposit > 0) {
            uint256 refund = buyerPremiumDeposit;
            buyerPremiumDeposit = 0;
            collateralToken.safeTransfer(buyer, refund);
        }

        emit Settled(buyer, payout);
    }

    /// @notice Expire if maturity reached with no credit event
    /// @dev Returns collateral to seller and remaining deposit to buyer
    function expire() external nonReentrant {
        require(status == CDSStatus.Active, "CDSContract: not active");
        require(block.timestamp >= terms.maturity, "CDSContract: not matured");

        status = CDSStatus.Expired;

        // Process final premium payment
        uint256 accrued = PremiumEngine.accruedPremium(premiumState, block.timestamp);
        uint256 premiumPayment = accrued.min(buyerPremiumDeposit);
        if (premiumPayment > 0) {
            buyerPremiumDeposit -= premiumPayment;
            premiumState.totalPaid += premiumPayment;
            collateralToken.safeTransfer(seller, premiumPayment);
        }

        // Return collateral to seller
        if (collateralPosted > 0) {
            uint256 collateral = collateralPosted;
            collateralPosted = 0;
            collateralToken.safeTransfer(seller, collateral);
        }

        // Return unused premium deposit to buyer
        if (buyerPremiumDeposit > 0) {
            uint256 refund = buyerPremiumDeposit;
            buyerPremiumDeposit = 0;
            collateralToken.safeTransfer(buyer, refund);
        }

        emit Expired(block.timestamp);
    }

    // --- View Functions ---

    function getStatus() external view override returns (CDSStatus) {
        return status;
    }

    function getTerms() external view override returns (CDSTerms memory) {
        return terms;
    }

    /// @notice Get accrued premium owed but not yet paid
    function getAccruedPremium() external view returns (uint256) {
        return PremiumEngine.accruedPremium(premiumState, block.timestamp);
    }

    /// @notice Check if both buyer and seller are set
    function isFullyMatched() external view returns (bool) {
        return buyer != address(0) && seller != address(0);
    }

    /// @notice Get remaining time to maturity
    function timeToMaturity() external view returns (uint256) {
        if (block.timestamp >= terms.maturity) return 0;
        return terms.maturity - block.timestamp;
    }
}
