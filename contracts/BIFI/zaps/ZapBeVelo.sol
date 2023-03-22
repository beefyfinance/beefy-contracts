// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/access/Ownable.sol";
import "../interfaces/common/ISolidlyRouter.sol";

interface IbeVelo {
    function deposit(uint amount) external;
}

contract ZapBeVelo is Ownable {
    using SafeERC20 for IERC20;

    // needed addresses
    address public beVelo;
    address public velo;
    address public router; 
    ISolidlyRouter.Routes[] public route; 

    constructor(
        address _router, 
        ISolidlyRouter.Routes[] memory _route
    ) {
        for (uint i; i < _route.length; ++i) {
            route.push(_route[i]);
        }

        velo = route[0].from;
        beVelo = route[route.length - 1].to;
        router = _router;

        IERC20(velo).safeApprove(router, type(uint256).max);
        IERC20(velo).safeApprove(beVelo, type(uint256).max);
    }

    function deposit(uint256 _amount) external {
        IERC20(velo).safeTransferFrom(msg.sender, address(this), _amount);
        uint256[] memory swapAmount = ISolidlyRouter(router).getAmountsOut(_amount, route);

        if (swapAmount[swapAmount.length - 1 ] > _amount) {
            ISolidlyRouter(router).swapExactTokensForTokens(_amount, swapAmount[swapAmount.length - 1], route, msg.sender, block.timestamp);
        } else {
            uint256 beforeMint = IERC20(beVelo).balanceOf(address(this));
            IbeVelo(beVelo).deposit(_amount);
            uint256 usersBal = IERC20(beVelo).balanceOf(address(this)) - beforeMint;

            IERC20(beVelo).safeTransfer(msg.sender, usersBal);
        }
    }

     // recover any tokens sent on error
    function inCaseTokensGetStuck(address _token, bool _native) external onlyOwner {
        if (_native) {
            uint256 _nativeAmount = address(this).balance;
            (bool sent,) = msg.sender.call{value: _nativeAmount}("");
            require(sent, "Failed to send Ether");
        } else {
            uint256 _amount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, _amount);
        }
    }
}