// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

    address payable constant public multisig = payable(address(0x37EA21Cb5e080C27a47CAf767f24a8BF7Fcc7d4d));

    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address public router = address(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    address public pantherRouter = address(0x24f7C33ae5f77e2A9ECeed7EA858B4ca2fa1B7eC);
    address public panther = address(0x1f546aD641B56b86fD9dCEAc473d1C7a357276B7);

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
        IRouter(_router).swapExactTokensForETHSupportingFeeOnTransferTokens(tokenBal, 0, _route, multisig, block.timestamp);
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
        IERC20(_token).safeTransfer(multisig, _amount);
    }

    function withdrawNative(uint256 _amount) external onlyAdmin {
        multisig.transfer(_amount);
    }

    function pantherToBNB() external onlyAdmin {
        swapToBNB(panther, pantherRouter);
    }

    receive() external payable {}
}