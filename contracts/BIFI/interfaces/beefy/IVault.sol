// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IStrategy.sol";

interface IVault {
    function deposit(uint256) external;
    function depositAll() external;
    function withdraw(uint256) external;
    function withdrawAll() external;
    function getPricePerFullShare() external view returns (uint256);
    function upgradeStrat() external;
    function balance() external view returns (uint256);
    function want() external view returns (IERC20);
    function strategy() external returns (IStrategy);
    function balanceOf(address account) external view returns (uint256);
}
