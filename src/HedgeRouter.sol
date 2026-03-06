// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IHedgeRouter} from "./interfaces/IHedgeRouter.sol";
import {IForgeVault} from "./interfaces/IForgeVault.sol";
import {ICDSContract} from "./interfaces/ICDSContract.sol";
import {ShieldFactory} from "./shield/ShieldFactory.sol";
import {ShieldPricer} from "./shield/ShieldPricer.sol";
import {PremiumEngine} from "./shield/PremiumEngine.sol";

/// @title HedgeRouter
/// @notice Composes Forge investing + Shield protection into a single atomic transaction.
/// @dev Stateless router — user is the direct owner of tranche tokens and CDS buyer position.
///      Token flow: user approves router → router pulls tokens → approves vault/CDS → executes.
contract HedgeRouter is IHedgeRouter, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    ShieldPricer public immutable pricer;
    ShieldFactory public immutable shieldFactory;
    address public pauseAdmin;

    constructor(address pricer_, address shieldFactory_, address pauseAdmin_) {
        require(pricer_ != address(0), "HedgeRouter: zero pricer");
        require(shieldFactory_ != address(0), "HedgeRouter: zero factory");
        require(pauseAdmin_ != address(0), "HedgeRouter: zero pause admin");
        pricer = ShieldPricer(pricer_);
        shieldFactory = ShieldFactory(shieldFactory_);
        pauseAdmin = pauseAdmin_;
    }

    /// @notice Invest in vault + buy protection on existing CDS atomically
    /// @param p Parameters: vault, trancheId, investAmount, cds address, maxPremium
    function investAndHedge(InvestAndHedgeParams calldata p) external override nonReentrant whenNotPaused {
        require(p.vault != address(0), "HedgeRouter: zero vault");
        require(p.cds != address(0), "HedgeRouter: zero cds");
        require(p.investAmount > 0, "HedgeRouter: zero invest");

        IERC20 token = IForgeVault(p.vault).underlyingAsset();

        // Pull invest + max premium from user
        uint256 totalPull = p.investAmount + p.maxPremium;
        token.safeTransferFrom(msg.sender, address(this), totalPull);

        // Invest in vault — shares and tranche tokens go to user
        token.approve(p.vault, p.investAmount);
        IForgeVault(p.vault).investFor(p.trancheId, p.investAmount, msg.sender);
        token.approve(p.vault, 0);

        // Buy protection — user becomes CDS buyer (verify seller exists so protection is backed)
        require(ICDSContract(p.cds).getStatus() == ICDSContract.CDSStatus.Active, "HedgeRouter: CDS not active");
        ICDSContract.CDSTerms memory cdsTerms = ICDSContract(p.cds).getTerms();
        token.approve(p.cds, p.maxPremium);
        ICDSContract(p.cds).buyProtectionFor(cdsTerms.protectionAmount, p.maxPremium, msg.sender);
        token.approve(p.cds, 0);

        // Return unused tokens (maxPremium - actualPremium)
        uint256 remaining = token.balanceOf(address(this));
        if (remaining > 0) {
            token.safeTransfer(msg.sender, remaining);
        }

        emit HedgeExecuted(msg.sender, p.vault, p.trancheId, p.investAmount, p.cds);
    }

    /// @notice Invest + create new CDS + buy protection atomically
    /// @dev Creates an unmatched CDS (no seller yet). Buyer's premium is escrowed and
    ///      returned via expire() if no seller joins before maturity.
    /// @param p Parameters including CDS creation terms
    function createAndHedge(CreateAndHedgeParams calldata p) external override nonReentrant whenNotPaused {
        require(p.vault != address(0), "HedgeRouter: zero vault");
        require(p.investAmount > 0, "HedgeRouter: zero invest");
        require(p.protectionAmount > 0, "HedgeRouter: zero protection");

        IERC20 token = IForgeVault(p.vault).underlyingAsset();

        // Pull invest + max premium from user
        uint256 totalPull = p.investAmount + p.maxPremium;
        token.safeTransferFrom(msg.sender, address(this), totalPull);

        // Invest in vault
        token.approve(p.vault, p.investAmount);
        IForgeVault(p.vault).investFor(p.trancheId, p.investAmount, msg.sender);
        token.approve(p.vault, 0);

        // Create CDS via factory
        address cds = shieldFactory.createCDS(ShieldFactory.CreateCDSParams({
            referenceAsset: p.vault,
            protectionAmount: p.protectionAmount,
            premiumRate: p.premiumRate,
            maturity: p.maturity,
            collateralToken: address(token),
            oracle: p.oracle,
            paymentInterval: p.paymentInterval
        }));

        // Buy protection on new CDS
        token.approve(cds, p.maxPremium);
        ICDSContract(cds).buyProtectionFor(p.protectionAmount, p.maxPremium, msg.sender);
        token.approve(cds, 0);

        // Return unused tokens
        uint256 remaining = token.balanceOf(address(this));
        if (remaining > 0) {
            token.safeTransfer(msg.sender, remaining);
        }

        emit HedgeCreated(msg.sender, p.vault, p.trancheId, p.investAmount, cds);
    }

    // --- Pausable ---

    function pause() external {
        require(msg.sender == pauseAdmin, "HedgeRouter: not pause admin");
        _pause();
    }

    function unpause() external {
        require(msg.sender == pauseAdmin, "HedgeRouter: not pause admin");
        _unpause();
    }

    // --- Pause Admin Transfer (Two-Step) ---

    address public pendingPauseAdmin;

    event PauseAdminTransferStarted(address indexed previousAdmin, address indexed newAdmin);
    event PauseAdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    function transferPauseAdmin(address newAdmin) external {
        require(msg.sender == pauseAdmin, "HedgeRouter: not pause admin");
        require(newAdmin != address(0), "HedgeRouter: zero address");
        pendingPauseAdmin = newAdmin;
        emit PauseAdminTransferStarted(pauseAdmin, newAdmin);
    }

    function acceptPauseAdmin() external {
        require(msg.sender == pendingPauseAdmin, "HedgeRouter: not pending admin");
        emit PauseAdminTransferred(pauseAdmin, msg.sender);
        pauseAdmin = msg.sender;
        pendingPauseAdmin = address(0);
    }

    /// @notice Quote the estimated hedge cost for an investment
    /// @param vault ForgeVault to reference for pricing
    /// @param investAmount Protection notional (typically matches invest amount)
    /// @param tenorDays Duration of protection in days
    /// @return spreadBps Indicative annual spread in basis points
    /// @return estimatedPremium Estimated total premium in token units
    function quoteHedge(
        address vault,
        uint256 investAmount,
        uint256 tenorDays
    ) external view override returns (uint256 spreadBps, uint256 estimatedPremium) {
        spreadBps = pricer.getIndicativeSpread(vault, investAmount, tenorDays);
        estimatedPremium = PremiumEngine.calculateTotalPremium(investAmount, spreadBps, tenorDays);
    }
}
