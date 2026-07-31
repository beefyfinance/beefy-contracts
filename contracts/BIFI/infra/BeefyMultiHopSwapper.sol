// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IBeefySwapper } from "../interfaces/beefy/IBeefySwapper.sol";
import { SafeERC20, IERC20 } from "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BeefyMultiHopSwapper is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IBeefySwapper public swapper;

    error Slippage(uint amountOut, uint minAmountOut);

    function initialize(address _swapper) initializer external {
        __Ownable_init();
        swapper = IBeefySwapper(_swapper);
    }

    function swap(address[] calldata _path, uint _amountIn, uint _minAmountout) external {
        IERC20 startToken = IERC20(_path[0]);
        startToken.transferFrom(msg.sender, address(this), _amountIn);

        for (uint i; i < _path.length - 1; ++i) {
            IERC20 swapToken = IERC20(_path[i]);
            uint256 bal = swapToken.balanceOf(address(this));
            swapToken.safeApprove(address(swapper), 0);
            swapToken.safeApprove(address(swapper), bal);
            swapper.swap(_path[i], _path[i + 1], bal);
        }

        IERC20 endToken = IERC20(_path[_path.length -1]);
        uint endBal = endToken.balanceOf(address(this));

        if (endBal < _minAmountout) revert Slippage(endBal, _minAmountout);
        endToken.transfer(msg.sender, endBal);
    }

    function setSwapper(address _swapper) external onlyOwner {
        swapper = IBeefySwapper(_swapper);
    }
}