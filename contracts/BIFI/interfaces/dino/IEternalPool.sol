pragma solidity ^0.6.0;

interface IEternalPool {
    function pendingReward(address _user) external view returns (uint256);
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function emergencyWithdraw() external;
    function userInfo(address _user) external view returns (uint256, uint256);
}
