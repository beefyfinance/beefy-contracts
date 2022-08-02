// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IDelegateManagerCommon {
    function setDelegate(bytes32 _id, address _voter) external;
    function clearDelegate(bytes32 _id) external;
    function delegation(address _voteHolder, bytes32 _id) external view returns (address);
}