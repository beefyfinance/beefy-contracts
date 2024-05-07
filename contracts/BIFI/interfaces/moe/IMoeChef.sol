// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMoeChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
    function getDeposit(uint256 _pid, address _user) external view returns (uint256);
    function getPendingRewards(
        address _account,
        uint256[] calldata _pids
    ) external view returns (
        uint256[] memory _moeRewards,
        address[] memory _extraTokens,
        uint256[] memory _extraRewards
    );
}
