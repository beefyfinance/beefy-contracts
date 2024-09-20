// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../interfaces/beefy/IBeefySwapper.sol";
import "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";


interface IDaiUsds {
    function usdsToDai(address usr, uint256 wad) external;
}

contract SkyToNativeSwap {
    using SafeERC20 for IERC20;

    address public sky = 0x56072C95FAA701256059aa122697B133aDEd9279;
    address public usds = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public swapper = 0x8d6cE71ab8c98299c1956247CA9aaEC080DD2df3;
    address public daiUsds = 0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A;

    function swap(uint amount) external {
        IERC20(sky).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(sky).approve(swapper, amount);
        IBeefySwapper(swapper).swap(sky, usds, amount);

        uint bal = IERC20(usds).balanceOf(address(this));
        IERC20(usds).approve(daiUsds, bal);
        IDaiUsds(daiUsds).usdsToDai(address(this), bal);

        bal = IERC20(dai).balanceOf(address(this));
        IERC20(dai).approve(swapper, bal);
        IBeefySwapper(swapper).swap(dai, native, bal);

        IERC20(native).safeTransfer(msg.sender, IERC20(native).balanceOf(address(this)));
    }
}