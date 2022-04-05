// SPDX-License-Identifier: MIT

pragma solidity >0.6.0 <0.9.0;

interface ISolarChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256, uint256, uint256);
    function emergencyWithdraw(uint256 _pid) external;
    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (address[] calldata addresses, string[] calldata symbols, uint256[] calldata decimals, uint256[] calldata amounts);
}
