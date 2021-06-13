// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IVault.sol";

interface ISeededVault is IVault {
    function seed() external;
}
