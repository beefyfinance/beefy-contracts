// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IDCAStrategy {
    function deposit() external;
    function withdraw(uint256 amount) external;
    function beforeDeposit() external;
    function vault() external view returns (address);
    function want() external view returns (address);
    function reward() external view returns (address);
    function retireStrat() external;
}