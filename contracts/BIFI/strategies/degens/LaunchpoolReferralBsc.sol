// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

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

contract LaunchpoolReferralBsc is Ownable {
    using SafeERC20 for IERC20;

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

    function owner() public view override returns (address) {
        if (super.owner() == address(0)) {
            return address(0x982F264ce97365864181df65dF4931C593A515ad);
        } else return super.owner();
    }

    function swap(address[] memory _route, address _router) public onlyAdmin {
        address token = _route[0];
        uint256 tokenBal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeIncreaseAllowance(_router, tokenBal);
        IRouter(_router).swapExactTokensForETHSupportingFeeOnTransferTokens(tokenBal, 0, _route, owner(), now);
    }

    function swapToNative(address _token, address _router) public onlyAdmin {
        address[] memory nativeRoute = new address[](2);
        nativeRoute[0] = _token;
        nativeRoute[1] = native();
        swap(nativeRoute, _router);
    }

    function swapToNative(address _token) external onlyAdmin {
        swapToNative(_token, defaultRouter());
    }

    function withdrawToken(address _token, uint256 _amount) external onlyAdmin {
        IERC20(_token).safeTransfer(owner(), _amount);
    }

    function withdrawNative(uint256 _amount) external onlyAdmin {
        payable(owner()).transfer(_amount);
    }

    function native() public pure returns (address) {return address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);}
    function defaultRouter() public pure returns (address) {return pcsRouter();}
    function pcsRouter() public pure returns (address) {return address(0x10ED43C718714eb63d5aA57B78B54704E256024E);}
    function apeRouter() public pure returns (address) {return address(0xC0788A3aD43d79aa53B09c2EaCc313A787d1d607);}

    function pearToBNB() public onlyAdmin {
        swapToNative(address(0xdf7C18ED59EA738070E665Ac3F5c258dcc2FBad8), apeRouter());
    }

    function AAA_swapAll() external onlyAdmin {
        pearToBNB();
    }

    receive() external payable {}
}