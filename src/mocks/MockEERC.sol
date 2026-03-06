// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockEERC
/// @notice A standard ERC20 that mimics eERC's interface for unit testing.
/// @dev In production, this is replaced by EncryptedERC (Standalone mode).
///      The mock skips ZK proofs, encryption, and registrar checks.
///      It preserves the key behavioral contract:
///      - onlyOwner can mint (owner = ForgeVault)
///      - transfers trigger a hook callback to the vault
///      - balances are plain uint256 (no encryption)
contract MockEERC is ERC20, Ownable {
    uint8 private immutable _decimals;

    /// @notice Address that receives transfer hook callbacks
    address public transferHookTarget;

    /// @notice Selector for the transfer hook callback
    bytes4 public constant TRANSFER_HOOK_SELECTOR =
        bytes4(keccak256("onShareTransfer(address,address,uint256)"));

    event TransferHookCalled(address indexed from, address indexed to, uint256 amount);

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address owner_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Set the address that should receive transfer hook callbacks
    /// @param target The contract to call onShareTransfer on
    function setTransferHookTarget(address target) external onlyOwner {
        transferHookTarget = target;
    }

    /// @notice Mint tokens to a user. In production, this requires a ZK proof.
    /// @dev onlyOwner — the vault is the owner/minter
    function mint(address to, uint256 amount) external virtual onlyOwner {
        _mint(to, amount);
    }

    /// @notice Burn tokens from a user. In production, this requires a ZK proof.
    /// @dev onlyOwner — the vault controls burns
    function burn(address from, uint256 amount) external virtual onlyOwner {
        _burn(from, amount);
    }

    /// @notice Override transfer to include hook callback
    function transfer(address to, uint256 amount) public override returns (bool) {
        bool success = super.transfer(to, amount);
        if (success) {
            _callTransferHook(msg.sender, to, amount);
        }
        return success;
    }

    /// @notice Override transferFrom to include hook callback
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool success = super.transferFrom(from, to, amount);
        if (success) {
            _callTransferHook(from, to, amount);
        }
        return success;
    }

    function _callTransferHook(address from, address to, uint256 amount) internal virtual {
        if (transferHookTarget != address(0)) {
            (bool success,) = transferHookTarget.call(
                abi.encodeWithSelector(TRANSFER_HOOK_SELECTOR, from, to, amount)
            );
            require(success, "MockEERC: transfer hook failed");
            emit TransferHookCalled(from, to, amount);
        }
    }
}
