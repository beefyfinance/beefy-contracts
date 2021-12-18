// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IBlizzMasterChef {
    function deposit(address _token, uint256 _amount) external;
    function withdraw(address _token, uint256 _amount) external;
    function claim(address _user, address[] calldata _tokens) external;
    function emergencyWithdraw(address _token) external;
    function userInfo(address _token, address _user) external view returns (uint256, uint256);
    function claimableReward(address _user, address[] calldata _tokens) external view returns (uint256[] memory);
}

interface IBlizzMultiFeeDistribution {
    function exit(bool _claim) external;
}

interface IBlizzIncentivesController {
    function claim(address _user, address[] calldata _tokens) external;
    function claimableReward(address _user, address[] calldata _tokens) external view returns (uint256[] memory);
}