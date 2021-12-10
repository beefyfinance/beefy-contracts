// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./IBeefyRegistryStrategy.sol";

interface IBeefyRegistryVault is IERC20Upgradeable {
    function name() external view returns (string memory);
    function deposit(uint256) external;
    function depositAll() external;
    function withdraw(uint256) external;
    function withdrawAll() external;
    function getPricePerFullShare() external view returns (uint256);
    function upgradeStrat() external;
    function balance() external view returns (uint256);
    function want() external view returns (IERC20Upgradeable);
    function strategy() external view returns (IBeefyRegistryStrategy);
}