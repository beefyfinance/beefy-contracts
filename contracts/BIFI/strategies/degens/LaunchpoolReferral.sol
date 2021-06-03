// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IRouter {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

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

    address payable constant public multisig = payable(address(0x37EA21Cb5e080C27a47CAf767f24a8BF7Fcc7d4d));

    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public busd = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    address public router = address(0x10ED43C718714eb63d5aA57B78B54704E256024E);

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

    function swapToBNB(address _token) external onlyAdmin {
        uint256 tokenBal = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeIncreaseAllowance(router, tokenBal);

        address[] memory wbnbRoute = new address[](2);
        wbnbRoute[0] = _token;
        wbnbRoute[1] = wbnb;

        IRouter(router).swapExactTokensForETHSupportingFeeOnTransferTokens(tokenBal, 0, wbnbRoute, multisig, now);
    }

    function swapToBUSD(address _token) external onlyAdmin {
        uint256 tokenBal = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeIncreaseAllowance(router, tokenBal);

        address[] memory busdRoute = new address[](2);
        busdRoute[0] = _token;
        busdRoute[1] = busd;

        IRouter(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(tokenBal, 0, busdRoute, multisig, now);
    }

    function withdrawToken(address _token, uint256 _amount) external onlyAdmin {
        IERC20(_token).safeTransfer(multisig, _amount);
    }

    function withdrawNative(uint256 _amount) external onlyAdmin {
        multisig.transfer(_amount);
    }

    receive() external payable {}
}