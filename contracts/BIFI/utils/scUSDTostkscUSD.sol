// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";


interface ITeller {
    function deposit(address depositAsset, uint256 depositAmount, uint256 minimumMint)
    external
    returns (uint256 shares);
}

contract scUSDTostkscUSD {
    using SafeERC20 for IERC20;

    address public scUSD = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;
    address public stkscUSD = 0x4D85bA8c3918359c78Ed09581E5bc7578ba932ba;
    ITeller public teller = ITeller(0x5e39021Ae7D3f6267dc7995BB5Dd15669060DAe0);

    function swap(uint amount) external {
        IERC20(scUSD).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(scUSD).approve(stkscUSD, amount);
        teller.deposit(scUSD, amount, 0);
        IERC20(stkscUSD).safeTransfer(msg.sender, IERC20(stkscUSD).balanceOf(address(this)));
    }
}