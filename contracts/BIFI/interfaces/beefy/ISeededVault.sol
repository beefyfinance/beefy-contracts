// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "./IVault.sol";

interface ISeededVault is IVault {
    function seed() external;
}
