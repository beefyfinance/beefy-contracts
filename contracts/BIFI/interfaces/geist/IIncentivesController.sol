// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IIncentivesController {
    function claimableReward(address _user, address[] calldata _tokens) external view returns (uint256[] memory);
    function claim(address _user, address[] calldata _tokens) external;
}