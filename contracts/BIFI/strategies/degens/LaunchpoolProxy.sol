// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/ProxyAdmin.sol";

contract LaunchpoolProxy is TransparentUpgradeableProxy, ProxyAdmin {
    constructor(address _logic) public TransparentUpgradeableProxy(_logic, msg.sender, ''){}
}