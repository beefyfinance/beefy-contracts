// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IPermit2 } from "./IPermit2.sol";

/**
 * @title Zap router interface
 * @author kexley, Beefy
 * @notice Interface for zap router that contains the structs for orders and routes
 */
interface IBeefyZapRouter {
    /**
     * @dev Input token and amount used in a step of the zap
     * @param token Address of token
     * @param amount Amount of token
     */
    struct Input {
        address token;
        uint256 amount;
    }

    /**
     * @dev Output token and amount from the end of the zap
     * @param token Address of token
     * @param minOutputAmount Minimum amount of token received
     */
    struct Output {
        address token;
        uint256 minOutputAmount;
    }

    /**
     * @dev External call at the end of zap
     * @param target Target address to be called
     * @param value Ether value of the call
     * @param data Payload to call target address with
     */
    struct Relay {
        address target;
        uint256 value;
        bytes data;
    }

    /**
     * @dev Token relevant to the current step of the route
     * @param token Address of token
     * @param index Location in the data that the balance of the token should be inserted
     */
    struct StepToken {
        address token;
        int32 index;
    }

    /**
     * @dev Step in a route
     * @param target Target address to be called
     * @param value Ether value to call the target address with
     * @param data Payload to call target address with
     * @param tokens Tokens relevant to the step that require approvals or their balances inserted
     * into the data
     */
    struct Step {
        address target;
        uint256 value;
        bytes data;
        StepToken[] tokens;
    }

    /**
     * @dev Order created by the user
     * @param inputs Tokens and amounts to be pulled from the user
     * @param outputs Tokens and minimums to be sent to recipient
     * @param relay External call to make after zap is completed
     * @param user Source of input tokens
     * @param recipient Destination of output tokens
     */
    struct Order {
        Input[] inputs;
        Output[] outputs;
        Relay relay;
        address user;
        address recipient;
    }

    /**
     * @notice Execute an order directly
     * @param _order Order created by the user
     * @param _route Route supplied by user
     */
    function executeOrder(Order calldata _order, Step[] calldata _route) external payable;

    /**
     * @notice Execute an order on behalf of a user
     * @param _permit Token permits from Permit2 with the order as witness data signed by user
     * @param _order Order created by user that was signed in the permit
     * @param _signature Signature from user of combined permit and order
     * @param _route Route supplied by user or third-party
     */
    function executeOrder(
        IPermit2.PermitBatchTransferFrom calldata _permit,
        Order calldata _order,
        bytes calldata _signature,
        Step[] calldata _route
    ) external;

    /**
     * @notice Pause the contract from carrying out any more zaps
     * @dev Only owner can pause
     */
    function pause() external;

    /**
     * @notice Unpause the contract to allow new zaps
     * @dev Only owner can unpause
     */
    function unpause() external;

    /**
     * @notice Permit2 immutable address
     */
    function permit2() external view returns (address);

    /**
     * @notice Token manager immutable address
     */
    function tokenManager() external view returns (address);
}
