// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/common/IUniswapRouterETH.sol";
import "../interfaces/beefy/IVault.sol";
import "../interfaces/beefy/IStrategyComplete.sol";

contract StrategistBuyback is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public input;
    address public output;

    address public bifiMaxi;
    address public unirouter;

    address[] public inputToOutputRoute;

    constructor(
        address _bifiMaxi,
        address _unirouter, 
        address[] memory _inputToOutputRoute
    ) public {
        unirouter = _unirouter;
        bifiMaxi = _bifiMaxi;

        _setInputToOutputRoute(_inputToOutputRoute);

        IERC20(input).safeApprove(unirouter, uint256(-1));
    }

    function depositAllIntoBifiMaxi() external onlyOwner {
        _depositAllIntoBifiMaxi();
    }

    function withdrawAllFromBifiMaxi() external onlyOwner {
        _withdrawAllFromBifiMaxi();
    }

    // Convert and send to beefy maxi
    function harvest() public {
        uint256 inputBal = IERC20(input).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(inputBal, 0, inputToOutputRoute, address(this), now);

        _depositAllIntoBifiMaxi();
    }

    function setVaultStrategist(address _vault, address _newStrategist) external onlyOwner {
        address strategy = address(IVault(_vault).strategy());
        address strategist = IStrategyComplete(strategy).strategist();
        require(strategist == address(this), "Strategist buyback is not the strategist for the target vault");
        IStrategyComplete(strategy).setStrategist(_newStrategist);
    }

    function setUnirouter(address _unirouter) external onlyOwner {
        IERC20(input).safeApprove(_unirouter, uint256(-1));
        IERC20(input).safeApprove(unirouter, 0);

        unirouter = _unirouter;
    }

    function setInputToOutputRoute(address[] memory _route) external onlyOwner {
        _setInputToOutputRoute(_route);
    }
    
    function withdrawToken(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    function _depositAllIntoBifiMaxi() internal {
        IVault(bifiMaxi).depositAll();
    }

    function _withdrawAllFromBifiMaxi() internal {
        IVault(bifiMaxi).withdrawAll();
    }

    function _setInputToOutputRoute(address[] memory _route) internal {
        input = _route[0];
        output = _route[_route.length - 1];
        inputToOutputRoute = _route;
    }
}