// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICakePool {
    function deposit(uint256 _amount, uint256 _lockDuration) external;
    function balanceOf() external view returns (uint256);
    function totalShares() external view returns (uint256);
    function performanceFeeContract() external view returns (uint256);
    function withdrawAll() external;
    function unlock(address _user) external;
    function token() external view returns (address);
    function MIN_DEPOSIT_AMOUNT() external view returns (uint256);
    function getPricePerFullShare() external view returns (uint256);

    function userInfo(address _user)
        external view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, bool, uint256);
}