// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;


interface IMasterChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256, uint256, uint256);
    function emergencyWithdraw(uint256 _pid) external;
    function pendingTokens(uint256 _pid, address _user) external view returns (
        address[] memory addresses,
        // it's really a string[] but 0.6.0 don't support it 
        // Original error: UnimplementedFeatureError: Nested arrays not yet implemented.
        string/*[]*/  memory symbols,
        uint256[] memory decimals,
        uint256[] memory amounts
    );
}
