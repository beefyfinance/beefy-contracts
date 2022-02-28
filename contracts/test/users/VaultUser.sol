// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

// Interfaces
import {IBeefyVaultV6} from "../../BIFI/interfaces/beefy/IBeefyVaultV6.sol";

import {IERC20Like} from "../interfaces/IERC20Like.sol";

contract VaultUser {

    /*                 */
    /* ERC20 Functions */
    /*                 */

    function infiniteApprove(address token_, address spender_) external {
        approve(token_, spender_, type(uint256).max);
    }

    function approve(address token_, address spender_, uint256 amount_) public {
        IERC20Like(token_).approve(spender_, amount_);
    }

    /*                 */
    /* Vault Functions */
    /*                 */

    function deposit(IBeefyVaultV6 vault_, uint256 amount_) external returns (uint256 mooShares_) {
        vault_.deposit(amount_);
        mooShares_ = vault_.balanceOf(address(this));
    }

    function depositAll(IBeefyVaultV6 vault_) external returns (uint256 mooShares_) {
        vault_.depositAll();
        mooShares_ = vault_.balanceOf(address(this));
    }

    function withdraw(IBeefyVaultV6 vault_, uint256 shares_) external returns (uint256 want_) {
        vault_.withdraw(shares_);
        want_ = IERC20Like(vault_.want()).balanceOf(address(this));
    }

    function withdrawAll(IBeefyVaultV6 vault_) external returns (uint256 want_) {
        vault_.withdrawAll();
        want_ = IERC20Like(vault_.want()).balanceOf(address(this));

    }

}