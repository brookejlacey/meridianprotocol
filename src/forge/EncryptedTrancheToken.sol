// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {MockEERC} from "../mocks/MockEERC.sol";
import {ITrancheToken} from "../interfaces/ITrancheToken.sol";

/// @title EncryptedTrancheToken
/// @notice Tranche token backed by MockEERC (simulated eERC Standalone) for Phase 1C.
/// @dev In production, MockEERC would be replaced by EncryptedERC (Standalone mode)
///      with real ZK proofs for mint/burn/transfer. The behavioral contract is identical:
///      - Only the vault (owner) can mint and burn
///      - Transfers call ForgeVault.onShareTransfer() to keep plaintext mirrors in sync
///      - The hook MUST succeed or the transfer reverts (mirror sync is mandatory)
///
///      Key differences from TrancheToken:
///      - Access control: Ownable.onlyOwner instead of custom onlyVault modifier
///      - Hook mechanism: overridden transfer()/transferFrom() instead of _update() override
///      - Error type: OwnableUnauthorizedAccount(address) instead of string revert
///
///      Inherits from MockEERC:
///      - mint(address, uint256) external onlyOwner
///      - burn(address, uint256) external onlyOwner
///      - transfer()/transferFrom() with hook callbacks
///      - Standard ERC20 via OpenZeppelin
///
///      Implements ITrancheToken:
///      - vault() view — returns owner()
///      - trancheId() view — tranche index (0=Senior, 1=Mezz, 2=Equity)
///      - ShareTransferHook event on user-to-user transfers
contract EncryptedTrancheToken is MockEERC, ITrancheToken {
    uint8 public override trancheId;

    constructor(
        string memory name_,
        string memory symbol_,
        address vault_,
        uint8 trancheId_
    ) MockEERC(name_, symbol_, 18, vault_) {
        require(trancheId_ < 3, "EncryptedTrancheToken: invalid tranche id");
        trancheId = trancheId_;
        // Auto-setup: vault is both owner AND transfer hook target
        transferHookTarget = vault_;
    }

    /// @notice Returns the vault address (the Ownable owner)
    function vault() external view override returns (address) {
        return owner();
    }

    // --- Explicit overrides required by Solidity (same signature in MockEERC + ITrancheToken) ---

    function mint(address to, uint256 amount) external override(MockEERC, ITrancheToken) onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external override(MockEERC, ITrancheToken) onlyOwner {
        _burn(from, amount);
    }

    /// @notice Override hook to require success and emit ITrancheToken.ShareTransferHook
    /// @dev MockEERC silently swallows hook failures; we require success because
    ///      plaintext mirrors MUST stay in sync with token balances.
    function _callTransferHook(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (transferHookTarget != address(0)) {
            (bool success,) = transferHookTarget.call(
                abi.encodeWithSelector(TRANSFER_HOOK_SELECTOR, from, to, amount)
            );
            require(success, "EncryptedTrancheToken: hook failed");
            emit ShareTransferHook(from, to, amount);
        }
    }
}
