// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/**
 * @title Permit2 interface
 * @author kexley, Beefy
 * @notice Interface for Permit2
 */
interface IPermit2 {
    /**
     * @dev Token and amount in a permit message
     * @param token Address of token to transfer
     * @param amount Amount of token to transfer
     */
    struct TokenPermissions {
        address token;
        uint256 amount;
    }

    /**
     * @dev Batched permit with the unique nonce and deadline
     * @param permitted Tokens and corresponding amounts permitted for a transfer
     * @param nonce Unique value for every token owner's signature to prevent signature replays
     * @param deadline Deadline on the permit signature
     */
    struct PermitBatchTransferFrom {
        TokenPermissions[] permitted;
        uint256 nonce;
        uint256 deadline;
    }

    /**
     * @dev Transfer details for permitBatchTransferFrom
     * @param to Recipient of tokens
     * @param requestedAmount Amount to transfer
     */
    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }

    /**
     * @notice Consume a permit2 message and transfer tokens
     * @param permit Batched permit
     * @param transferDetails Recipient and amount of tokens to transfer
     * @param owner Source of tokens
     * @param witness Verified order data that was witnessed in the permit2 signature
     * @param witnessTypeString Order function string used to create EIP-712 type string
     * @param signature Signature from user
     */
    function permitWitnessTransferFrom(
        PermitBatchTransferFrom memory permit,
        SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external;

    /**
     * @notice Domain separator to differentiate the chain a permit exists on
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
