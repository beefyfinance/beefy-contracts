// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

interface IBeefyRegistry {
    function allVaultAddresses() external view returns (address[] memory);

    function getVaultCount() external view returns (uint256 count);
}
