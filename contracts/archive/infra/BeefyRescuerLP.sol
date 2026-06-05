// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/access/Ownable.sol";

import "../interfaces/common/IUniswapV2Pair.sol";
import "../interfaces/common/IUniswapRouterETH.sol";

contract BeefyRescuerLP is Ownable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Addresses used
    address public source;
    address public destination;
    address public unirouter;
    address public keeper;

    // Routes
    address[] public lp0ToLp1Route;
    address[] public lp1ToLp0Route;

    // Events
    event Rescue(address token, uint256 tokenAmount, uint256 wantAmount);
    event InCaseTokensGetStuck(address token, uint256 amount);

    constructor(
        address _want,
        address _source,
        address _destination,
        address _unirouter,
        address _keeper
    ) {
        want = _want;
        source = _source;
        destination = _destination;
        unirouter = _unirouter;
        keeper = _keeper;

        lpToken0 = IUniswapV2Pair(want).token0();
        lpToken1 = IUniswapV2Pair(want).token1();

        lp0ToLp1Route = [lpToken0, lpToken1];
        lp1ToLp0Route = [lpToken1, lpToken0];

        IERC20(lpToken0).safeApprove(unirouter, type(uint).max);
        IERC20(lpToken1).safeApprove(unirouter, type(uint).max);
    }

    // checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    // rescue one of the tokens in the LP from old contract, add liquidity and send to new contract
    function rescue(address _token) external onlyManager {
        require(_token == lpToken0 || _token == lpToken1, "not in LP");

        uint256 tokenBal = IERC20(_token).balanceOf(source);
        IERC20(_token).safeTransferFrom(source, address(this), tokenBal);

        _swap(_token);
        _addLiquidity();

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).safeTransfer(destination, wantBal);
        emit Rescue(_token, tokenBal, wantBal);
    }

    function _swap(address _token) internal {
        uint256 halfBal = IERC20(_token).balanceOf(address(this)) / 2;
        address[] memory route = _token == lpToken0 ? lp0ToLp1Route : lp1ToLp0Route;
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(
            halfBal, 0, route, address(this), block.timestamp
        );
    }

    function _addLiquidity() internal {
        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IUniswapRouterETH(unirouter).addLiquidity(
            lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp
        );
    }

    function inCaseTokensGetStuck(address _token) external onlyOwner {
        uint256 tokenBal = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, tokenBal);
        emit InCaseTokensGetStuck(_token, tokenBal);
    }

    function lp0ToLp1() external view returns (address[] memory) {
        return lp0ToLp1Route;
    }

    function lp1ToLp0() external view returns (address[] memory) {
        return lp1ToLp0Route;
    }
}
