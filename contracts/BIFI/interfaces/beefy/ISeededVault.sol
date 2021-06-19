// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

import "./IVault.sol";

interface ISeededVault is IVault {
    function seed() external;
}
