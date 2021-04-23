// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IStrategy.sol";

interface IVault is IERC20 {
    function deposit(uint256 _amount) external;
    function depositAll() external;
    function withdraw(uint256 _shares) external;
    function withdrawAll() external;
    function getPricePerFullShare() external view returns (uint256);
    function proposeStrat(IStrategy _implementation) external;
    function upgradeStrat() external;
    function balance() external view returns (uint256);
    function want() external view returns (IERC20);
    function strategy() external view returns (IStrategy);
}
