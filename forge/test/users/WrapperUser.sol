// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

// Interfaces
import {IWrapper} from "../interfaces/IWrapper.sol";

import {IERC20Like} from "../interfaces/IERC20Like.sol";

contract WrapperUser {

    /*                 */
    /* ERC20 Functions */
    /*                 */

    function infiniteApprove(address token_, address spender_) external {
        approve(token_, spender_, type(uint256).max);
    }

    function approve(address token_, address spender_, uint256 amount_) public {
        IERC20Like(token_).approve(spender_, amount_);
    }

    /*                   */
    /* Wrapper Functions */
    /*                   */

    function deposit(IWrapper wrapper_, uint256 amount_) external returns (uint256 mooShares_) {
        wrapper_.deposit(amount_, address(this));
        mooShares_ = wrapper_.balanceOf(address(this));
    }

    function mint(IWrapper wrapper_, uint256 sharesAmount_) external returns (uint256 mooShares_) {
        wrapper_.mint(sharesAmount_, address(this));
        mooShares_ = wrapper_.balanceOf(address(this));
    }

    function depositAll(IWrapper wrapper_) external returns (uint256 mooShares_) {
        uint256 asset_ = IERC20Like(wrapper_.asset()).balanceOf(address(this));
        wrapper_.deposit(asset_, address(this));
        mooShares_ = wrapper_.balanceOf(address(this));
    }

    function withdraw(IWrapper wrapper_, uint256 assets_) external returns (uint256 asset_) {
        wrapper_.withdraw(assets_, address(this), address(this));
        asset_ = IERC20Like(wrapper_.asset()).balanceOf(address(this));
    }

    function redeem(IWrapper wrapper_, uint256 shares_) external returns (uint256 asset_) {
        wrapper_.redeem(shares_, address(this), address(this));
        asset_ = IERC20Like(wrapper_.asset()).balanceOf(address(this));
    }

    function withdrawAll(IWrapper wrapper_) external returns (uint256 asset_) {
        uint256 mooShares_ = wrapper_.balanceOf(address(this));
        wrapper_.redeem(mooShares_, address(this), address(this));
        asset_ = IERC20Like(wrapper_.asset()).balanceOf(address(this));
    }

    function wrap(IWrapper wrapper_, uint256 shares_) external {
        wrapper_.wrap(shares_);
    }

    function wrapAll(IWrapper wrapper_) external {
        wrapper_.wrapAll();
    }

    function unwrap(IWrapper wrapper_, uint256 shares_) external {
        wrapper_.unwrap(shares_);
    }

    function unwrapAll(IWrapper wrapper_) external {
        wrapper_.unwrapAll();
    }
}
