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

contract LaunchpoolReferralPolygon is Ownable {
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

    function native() public pure returns (address) {return address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);}
    function defaultRouter() public pure returns (address) {return quickRouter();}
    function quickRouter() public pure returns (address) {return address(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);}
    function sushiRouter() public pure returns (address) {return address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);}
    function waultRouter() public pure returns (address) {return address(0x3a1D87f206D12415f5b0A33E786967680AAb4f6d);}

    function spadeToMatic() external onlyAdmin {
        swapToNative(address(0xf5EA626334037a2cf0155D49eA6462fDdC6Eff19), sushiRouter());
    }

    function pearToMatic() external onlyAdmin {
        swapToNative(address(0xc8bcb58caEf1bE972C0B638B1dD8B0748Fdc8A44), waultRouter());
    }

    receive() external payable {}
}