// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../interfaces/beefy/IBeefySwapper.sol";
import "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";

contract mPendleToNativeSwap {
    using SafeERC20 for IERC20;

    address public mPendle = 0xB688BA096b7Bb75d7841e47163Cd12D18B36A5bF;
    address public pendle = 0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8;
    address public native = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public swapper = 0x62Fc95FBa4b802aC13017aAa65cA62FfcE6DF0eA;

    function swap(uint amount) external {
        IERC20(mPendle).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(mPendle).approve(swapper, amount);
        IBeefySwapper(swapper).swap(mPendle, pendle, amount);

        uint bal = IERC20(pendle).balanceOf(address(this));
        IERC20(pendle).approve(swapper, bal);
        IBeefySwapper(swapper).swap(pendle, native, bal);

        IERC20(native).safeTransfer(msg.sender, IERC20(native).balanceOf(address(this)));
    }
}