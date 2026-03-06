// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title MockTeleporter
/// @notice Simulates Avalanche ICM Teleporter messaging for single-chain testing.
/// @dev Stores messages and allows manual delivery. In production, Teleporter handles
///      cross-chain message passing via AWM relayers.

/// @notice Minimal interface matching ITeleporterMessenger
interface IMockTeleporterMessenger {
    struct TeleporterMessageInput {
        bytes32 destinationBlockchainID;
        address destinationAddress;
        TeleporterFeeInfo feeInfo;
        uint256 requiredGasLimit;
        address[] allowedRelayerAddresses;
        bytes message;
    }

    struct TeleporterFeeInfo {
        address feeTokenAddress;
        uint256 amount;
    }

    function sendCrossChainMessage(TeleporterMessageInput calldata messageInput)
        external
        returns (bytes32 messageID);
}

/// @notice Minimal interface matching ITeleporterReceiver
interface IMockTeleporterReceiver {
    function receiveTeleporterMessage(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        bytes calldata message
    ) external;
}

contract MockTeleporter {
    struct PendingMessage {
        bytes32 sourceBlockchainID;
        address originSenderAddress;
        bytes32 destinationBlockchainID;
        address destinationAddress;
        bytes message;
        bool delivered;
    }

    /// @notice Simulated blockchain ID for the local chain
    bytes32 public localBlockchainID;

    /// @notice All queued messages
    PendingMessage[] public messages;

    /// @notice Count of messages sent
    uint256 public messageCount;

    event MessageSent(
        bytes32 indexed destinationBlockchainID,
        address indexed destinationAddress,
        uint256 messageIndex
    );

    event MessageDelivered(uint256 indexed messageIndex, address indexed destination);

    constructor(bytes32 localBlockchainID_) {
        localBlockchainID = localBlockchainID_;
    }

    /// @notice Simulate sending a cross-chain message
    function sendCrossChainMessage(
        bytes32 destinationBlockchainID,
        address destinationAddress,
        bytes calldata message,
        uint256 /* requiredGasLimit */
    ) external returns (uint256 messageIndex) {
        messageIndex = messages.length;
        messages.push(
            PendingMessage({
                sourceBlockchainID: localBlockchainID,
                originSenderAddress: msg.sender,
                destinationBlockchainID: destinationBlockchainID,
                destinationAddress: destinationAddress,
                message: message,
                delivered: false
            })
        );
        messageCount++;

        emit MessageSent(destinationBlockchainID, destinationAddress, messageIndex);
    }

    /// @notice Deliver a pending message to its destination (simulates relayer)
    /// @dev In testing, call this to simulate the cross-chain delivery
    function deliverMessage(uint256 messageIndex) external {
        PendingMessage storage msg_ = messages[messageIndex];
        require(!msg_.delivered, "Already delivered");
        msg_.delivered = true;

        IMockTeleporterReceiver(msg_.destinationAddress).receiveTeleporterMessage(
            msg_.sourceBlockchainID, msg_.originSenderAddress, msg_.message
        );

        emit MessageDelivered(messageIndex, msg_.destinationAddress);
    }

    /// @notice Get pending message count
    function pendingCount() external view returns (uint256 count) {
        for (uint256 i = 0; i < messages.length; i++) {
            if (!messages[i].delivered) count++;
        }
    }
}
