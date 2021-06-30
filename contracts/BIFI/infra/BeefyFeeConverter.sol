// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/common/IUniswapRouterETH.sol";

contract BeefyFeeConverter is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public input;
    address public output;

    address public beefyFeeRecipient;
    address public cowllector;
    address public unirouter;

    address[] public inputToOutputRoute;

    constructor(
        address _beefyFeeRecipient, 
        address _cowllector,
        address _unirouter, 
        address[] memory _inputToOutputRoute
    ) public {
        beefyFeeRecipient = _beefyFeeRecipient;
        cowllector = _cowllector;
        unirouter = _unirouter;

        input = _inputToOutputRoute[0];
        output = _inputToOutputRoute[_inputToOutputRoute.length - 1];
        inputToOutputRoute = _inputToOutputRoute;

        IERC20(input).safeApprove(unirouter, uint256(-1));
    }

    modifier onlyCowllector() {
        require(msg.sender == cowllector, "!cowllector");
        _;
    }

    // Convert and send to beefy fee recipient
    function harvest() public onlyCowllector {
        uint256 inputBal = IERC20(input).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(inputBal, 0, inputToOutputRoute, address(this), now);

        uint256 outputBal = IERC20(output).balanceOf(address(this));
        IERC20(output).safeTransfer(beefyFeeRecipient, outputBal);
    }

    function setFeeRecipient(address _beefyFeeRecipient) external onlyOwner {
        beefyFeeRecipient = _beefyFeeRecipient;
    }

    function setUnirouter(address _unirouter) external onlyOwner {
        IERC20(input).safeApprove(_unirouter, uint256(-1));
        IERC20(input).safeApprove(unirouter, 0);

        unirouter = _unirouter;
    }

    function setCowllector(address _cowllector) external onlyOwner {
        cowllector = _cowllector;
    }

    function setInputToOutputRoute(address[] memory _route) external onlyOwner {
        inputToOutputRoute = _route;
    }
    
    // Rescue locked funds sent by mistake
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != input, "!safe");
        require(_token != output, "!safe");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}