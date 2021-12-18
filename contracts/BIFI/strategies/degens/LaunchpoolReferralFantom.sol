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

interface ISummitReferrals {
    function getPendingReferralRewards(address user) external view returns (uint256);
    function redeemReferralRewards() external;
}

contract LaunchpoolReferralFantom is Ownable {
    using SafeERC20 for IERC20;

    bool initialized;

    function init() external {
        initialized = true;
    }

    mapping(address => bool) public admins;

    modifier onlyAdmin() {
        require(msg.sender == owner() || admins[msg.sender], "!admin");
        _;
    }

    function addAdmins(address[] memory _admins) external onlyOwner {
        uint len = _admins.length;
        for (uint i; i < len; i++) {
            admins[_admins[i]] = true;
        }
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
        if (tokenBal > 0) {
            IERC20(token).safeIncreaseAllowance(_router, tokenBal);
            IRouter(_router).swapExactTokensForETHSupportingFeeOnTransferTokens(tokenBal, 0, _route, owner(), now);
        }
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

    function native() public pure returns (address) {return address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);}
    function defaultRouter() public pure returns (address) {return spookyRouter();}
    function spookyRouter() public pure returns (address) {return address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);}
    function spiritRouter() public pure returns (address) {return address(0x16327E3FbDaCA3bcF7E38F5Af2599D2DDc33aE52);}

    function pearToFTM() public onlyAdmin {
        swapToNative(address(0x7C10108d4B7f4bd659ee57A53b30dF928244b354), spiritRouter());
    }

    function summitRefsToFTM() public onlyAdmin {
        ISummitReferrals referrals = ISummitReferrals(0x0B90dd88692Ec4fd4A77584713E3770057272B38);
        if (referrals.getPendingReferralRewards(address(this)) > 0) {
            referrals.redeemReferralRewards();
        }
        swapToNative(address(0x8F9bCCB6Dd999148Da1808aC290F2274b13D7994), spookyRouter());
    }

    function AAA_swapAll() external onlyAdmin {
        pearToFTM();
        summitRefsToFTM();
    }

    receive() external payable {}
}