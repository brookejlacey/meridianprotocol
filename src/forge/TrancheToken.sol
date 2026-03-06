// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ITrancheToken} from "../interfaces/ITrancheToken.sol";

/// @title TrancheToken
/// @notice ERC-20 token representing a position in a ForgeVault tranche.
/// @dev In production (Phase 1C), this will extend EncryptedERC (eERC Standalone mode)
///      instead of standard ERC-20. The transfer hook pattern remains the same.
///
///      Key behavior:
///      - Only the vault can mint and burn
///      - Transfers call ForgeVault.onShareTransfer() to keep plaintext mirrors in sync
///      - The hook MUST settle yield for both parties before updating shares
contract TrancheToken is ERC20, ITrancheToken {
    /// @dev Precomputed selector for onShareTransfer(address,address,uint256)
    bytes4 private constant ON_SHARE_TRANSFER_SELECTOR =
        bytes4(keccak256("onShareTransfer(address,address,uint256)"));

    address public override vault;
    uint8 public override trancheId;

    modifier onlyVault() {
        require(msg.sender == vault, "TrancheToken: not vault");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address vault_,
        uint8 trancheId_
    ) ERC20(name_, symbol_) {
        require(vault_ != address(0), "TrancheToken: zero vault");
        require(trancheId_ < 3, "TrancheToken: invalid tranche id");
        vault = vault_;
        trancheId = trancheId_;
    }

    /// @notice Mint tranche tokens to an investor
    /// @dev Only callable by the vault (on invest)
    function mint(address to, uint256 amount) external override onlyVault {
        _mint(to, amount);
    }

    /// @notice Burn tranche tokens from an investor
    /// @dev Only callable by the vault (on withdraw)
    function burn(address from, uint256 amount) external override onlyVault {
        _burn(from, amount);
    }

    /// @notice Hook called after every transfer (including mint/burn)
    /// @dev Calls ForgeVault.onShareTransfer() for user-to-user transfers.
    ///      Skips the hook for mints (from=0) and burns (to=0) since the vault
    ///      already handles share accounting in those cases.
    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);

        // Only call hook for user-to-user transfers (not mint/burn)
        if (from != address(0) && to != address(0)) {
            // Call vault to sync plaintext mirrors
            (bool success,) = vault.call(
                abi.encodeWithSelector(ON_SHARE_TRANSFER_SELECTOR, from, to, amount)
            );
            require(success, "TrancheToken: hook failed");
            emit ShareTransferHook(from, to, amount);
        }
    }
}
