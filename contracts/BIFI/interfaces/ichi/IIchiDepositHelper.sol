// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IIchiDepositHelper {
    function forwardDepositToICHIVault(address _vault, address _deployer, address _token, uint256 _amount, uint256 _minAmountOut, address _to) external;
}
