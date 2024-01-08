// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import "../../utils/UniV3Actions.sol";

contract CurveUniV3Adapter {

    address public router;
    IERC20 public token;
    bytes public path;

    function initialize(address _router, address _token, bytes calldata _path) external {
        assert(address(router) == address(0));
        router = _router;
        token = IERC20(_token);
        path = _path;
        token.approve(_router, type(uint).max);
    }

    function exchange(uint, uint, uint dx, uint) external {
        token.transferFrom(msg.sender, address(this), dx);
        UniV3Actions.swapV3WithDeadline(router, path, dx, msg.sender);
    }
}