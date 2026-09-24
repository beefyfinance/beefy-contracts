// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../interfaces/beefy/IBeefySwapper.sol";
import "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";

contract SwapperIfNotZero {
    using SafeERC20 for IERC20;

    address public swapper;

    constructor(address _swapper) {
        swapper = _swapper;
    }

    function swap(address from, address to, uint amount) external {
        if (amount == 0) return;

        IERC20(from).safeTransferFrom(msg.sender, address(this), amount);
        uint bal = IERC20(from).balanceOf(address(this));

        IERC20(from).approve(swapper, bal);
        IBeefySwapper(swapper).swap(from, to, bal);

        IERC20 out = IERC20(to);
        out.safeTransfer(msg.sender, out.balanceOf(address(this)));
    }
}