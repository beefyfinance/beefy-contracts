// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IRouter {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

contract LaunchpoolReferral is Ownable {
    using SafeERC20 for IERC20;

    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address public pcsV2Router = address(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address public router = pcsV2Router;

    address public honey = address(0xFa363022816aBf82f18a9C2809dCd2BB393F6AC5);

    mapping(address => bool) public admins;

    modifier onlyAdmin() {
        require(msg.sender == owner() || admins[msg.sender], "!admin");
        _;
    }

    function addAdmin(address admin) external onlyOwner {
        admins[admin] = true;
    }

    function removeAdmin(address admin) external onlyOwner {
        admins[admin] = false;
    }

    function setRouter(address _router) external onlyOwner {
        router = _router;
    }

    function swap(address[] memory _route, address _router) public onlyAdmin {
        address token = _route[0];
        uint256 tokenBal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeIncreaseAllowance(_router, tokenBal);
        IRouter(_router).swapExactTokensForETHSupportingFeeOnTransferTokens(tokenBal, 0, _route, owner(), now);
    }

    function swapToBNB(address _token, address _router) public onlyAdmin {
        address[] memory wbnbRoute = new address[](2);
        wbnbRoute[0] = _token;
        wbnbRoute[1] = wbnb;
        swap(wbnbRoute, _router);
    }

    function swapToBNB(address _token) external onlyAdmin {
        swapToBNB(_token, router);
    }

    function withdrawToken(address _token, uint256 _amount) external onlyAdmin {
        IERC20(_token).safeTransfer(owner(), _amount);
    }

    function withdrawNative(uint256 _amount) external onlyAdmin {
        payable(owner()).transfer(_amount);
    }

    function honeyToBNB() external onlyAdmin {
        swapToBNB(honey, pcsV2Router);
    }

    receive() external payable {}
}