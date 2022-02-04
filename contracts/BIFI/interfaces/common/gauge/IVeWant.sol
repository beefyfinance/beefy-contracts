// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVeWant {
    function create_lock(uint256 _amount, uint256 _unlockTime) external;
    function increase_amount(uint256 _amount) external;
    function increase_unlock_time(uint256 _unlockTime) external;
    function withdraw() external;
    function locked__end(address _user) external view returns (uint256);
    function balanceOf(address _user) external view returns (uint256);
    function token() external view returns (address);
}
