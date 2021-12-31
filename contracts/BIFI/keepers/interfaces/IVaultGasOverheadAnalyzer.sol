// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

interface IVaultGasOverheadAnalyzer is KeeperCompatibleInterface {
    function setUpkeepers(address[] memory upkeepers_, bool status_) external;

    function inCaseTokensGetStuck(address token_) external;

    function initialize() external;
}