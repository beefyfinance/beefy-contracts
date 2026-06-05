// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IBeefyStrategyEthCall {
    function vault() external view returns (address);

    function want() external view returns (IERC20Upgradeable);

    function beforeDeposit() external;

    function deposit() external;

    function withdraw(uint256) external;

    function balanceOf() external view returns (uint256);

    function balanceOfWant() external view returns (uint256);

    function balanceOfPool() external view returns (uint256);

    function harvest(address callFeeRecipient) external view; // Harvest with view.

    function retireStrat() external;

    function panic() external;

    function pause() external;

    function unpause() external;

    function paused() external view returns (bool);

    function unirouter() external view returns (address);

    function lpToken0() external view returns (address);

    function lpToken1() external view returns (address);

    function lastHarvest() external view returns (uint256);

    function callReward() external view returns (uint256);

    function harvestWithCallFeeRecipient(address callFeeRecipient) external view; // back compat call, with view
}
