// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import "../../utils/UniV3Actions.sol";

contract CurveUniV3Adapter {

    address public router;
    IERC20 public token;
    bytes public path;
    bool public withDeadline;

    function initialize(address _router, address _token, bytes calldata _path, bool _deadline) external {
        assert(address(router) == address(0));
        router = _router;
        token = IERC20(_token);
        path = _path;
        withDeadline = _deadline;
        token.approve(_router, type(uint).max);
    }

    function exchange(uint, uint, uint dx, uint) external {
        token.transferFrom(msg.sender, address(this), dx);
        if (withDeadline) {
            UniV3Actions.swapV3WithDeadline(router, path, dx, msg.sender);
        } else {
            UniV3Actions.swapV3(router, path, dx, msg.sender);
        }
    }
}