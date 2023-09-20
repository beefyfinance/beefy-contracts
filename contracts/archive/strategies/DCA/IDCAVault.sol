// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;
import "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
interface IDCAVault {
    function notifyRewardAmount(uint256 amount) external;
    function reward() external view returns (IERC20);
    function underlyingBalanceTotal() external view returns (uint256);
}