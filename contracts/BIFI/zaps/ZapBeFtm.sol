// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin-4/contracts/utils/math/SafeMath.sol";
import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/access/Ownable.sol";


interface IWrappedNative is IERC20 {
    function deposit() external payable;
    function withdraw(uint wad) external;
}

interface IbeFTM {
    function deposit(uint amount) external;
}

interface IUniswapRouterETH {
    function swapExactTokensForTokens(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

contract ZapbeFTM is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // needed addresses
    address public beFTM;
    address public wftm;
    address public router; 
    address[] public route; 

    constructor(
        address _beFTM,
        address _wftm,
        address _router, 
        address[] memory _route
    ) {
        beFTM = _beFTM;
        wftm = _wftm;
        router = _router;
        route = _route;

        IERC20(wftm).safeApprove(router, type(uint256).max);
        IERC20(wftm).safeApprove(beFTM, type(uint256).max);
    }

    function depositNative() external payable {
        uint256 _amount = msg.value;
        uint256 before = IERC20(wftm).balanceOf(address(this));
        IWrappedNative(wftm).deposit{value: _amount}();
        uint256 nativeBal = IERC20(wftm).balanceOf(address(this)).sub(before);

        uint256[]memory swapAmount = IUniswapRouterETH(router).getAmountsOut(nativeBal, route);

        if (swapAmount[swapAmount.length - 1 ] > nativeBal) {
            IUniswapRouterETH(router).swapExactTokensForTokens(nativeBal, swapAmount[swapAmount.length - 1], route, msg.sender, block.timestamp);
        } else {
            uint256 beforeMint = IERC20(beFTM).balanceOf(address(this));
            IbeFTM(beFTM).deposit(nativeBal);
            uint256 usersBal = IERC20(beFTM).balanceOf(address(this)).sub(beforeMint);

            IERC20(beFTM).safeTransfer(msg.sender, usersBal);
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

    receive () external payable {}
}