// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

pragma solidity >=0.6.0 <0.8.0;

interface IStrategy {
    function harvest() external;
    function callReward() external view returns (uint256);
}

pragma solidity >=0.6.0 <0.8.0;

contract BeefyMultiHarvest {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public native;

    constructor (address _native) public {
        native = _native;
    }

    function harvest (address[] memory strategies) external {
        for (uint256 i = 0; i < strategies.length; i++) {
            try IStrategy(strategies[i]).harvest() {} catch {}
        }

        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            IERC20(native).safeTransfer(tx.origin, nativeBal);
        }
    }

    function callReward (address[] memory strategies) external view returns (uint256[] memory rewards) {
        rewards = new uint256[](strategies.length);
        uint256 reward;

        for (uint256 i = 0; i < strategies.length; i++) {
            try IStrategy(strategies[i]).callReward() returns (uint256 _reward) {
                reward = _reward;
            } catch {
                reward = 0;
            }

            rewards[i] = reward;
        }
    }

}