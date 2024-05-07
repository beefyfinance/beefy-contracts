// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILendleChef {
    function claim(address _user, address[] calldata _tokens) external;
    function claimableReward(
        address _user,
        address[] calldata _tokens
    ) external view returns (uint256[] memory);
    function rewardMinter() external view returns (address);
}
