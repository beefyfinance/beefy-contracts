// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVaultFactory {
    event ProxyCreated(address proxy);
    function cloneVault() external returns (address);
    function instance() external view returns (address);
}
