// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./ManageableUpgradeable.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../interfaces/IPegSwap.sol";
import "../interfaces/IKeeperRegistry.sol";
import "../interfaces/IUpkeepRefunder.sol";

contract UpkeepRefunder is ManageableUpgradeable, IUpkeepRefunder {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // contracts
    IKeeperRegistry public keeperRegistry;
    IUniswapRouterETH public unirouter;
    IPegSwap public pegswap;

    address[] public nativeToLinkRoute;
    uint256 public shouldSwapToLinkThreshold;
    address public oracleLink;
    uint256 public upkeepId;

    function initialize(
        address keeperRegistry_,
        uint256 upkeepId_,
        address unirouter_,
        address[] memory nativeToLinkRoute_,
        address oracleLink_,
        address pegswap_,
        uint256 shouldSwapToLinkThreshold_
    ) external initializer {
        __Manageable_init();

        keeperRegistry = IKeeperRegistry(keeperRegistry_);
        upkeepId = upkeepId_;
        unirouter = IUniswapRouterETH(unirouter_);
        nativeToLinkRoute = nativeToLinkRoute_;
        oracleLink = oracleLink_;
        pegswap = IPegSwap(pegswap_);
        shouldSwapToLinkThreshold = shouldSwapToLinkThreshold_;

        _approveSpending();
    }

    /*      */
    /* Core */
    /*      */

    /**
     * @dev Harvester needs to approve refunder to allow transfer of tokens. Note that this function has open access control, anyone can refund the upkeep.
     * @return linkRefunded_ amount of link that was refunded to harvester.
     */
    function notifyRefundUpkeep() external override returns (uint256 linkRefunded_) {
        require(upkeepId > 0, "Invalid upkeep id.");

        if (balanceOfNative() >= shouldSwapToLinkThreshold) {
            linkRefunded_ = _addHarvestedFundsToUpkeep(upkeepId);
        }

        return linkRefunded_;
    }

    function withdrawAllLink() external onlyManager {
        uint256 amount = IERC20Upgradeable(LINK()).balanceOf(address(this));
        withdrawLink(amount);
    }

    function withdrawLink(uint256 amount_) public onlyManager {
        IERC20Upgradeable(LINK()).safeTransfer(msg.sender, amount_);
    }

    function wrapAllLinkToOracleVersion() external onlyManager {
        _wrapAllLinkToOracleVersion();
    }

    function unwrapToDexLink(uint256 amount_) public onlyManager {
        pegswap.swap(amount_, oracleLINK(), LINK());
    }

    function unwrapAllToDexLink() public onlyManager {
        unwrapToDexLink(balanceOfOracleLink());
    }

    /**
     * @notice Manually trigger native to link swap.
     */
    function swapNativeToLink() external onlyManager {
        _swapNativeToLink();
    }

    /**
     * @dev Rescues random funds stuck.
     * @param token_ address of the token to rescue.
     */
    function inCaseTokensGetStuck(address token_) external onlyManager {
        require(token_ != NATIVE() && token_ != LINK() && token_ != oracleLINK(), "Bad withdrawal.");

        IERC20Upgradeable token = IERC20Upgradeable(token_);

        uint256 amount = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, amount);
    }

    /*         */
    /* Helpers */
    /*         */

    function _addHarvestedFundsToUpkeep(uint256 upkeepId_) internal returns (uint256) {
        _swapNativeToLinkAndWrap();
        uint256 balance = balanceOfOracleLink();
        keeperRegistry.addFunds(upkeepId_, uint96(balance));
        return balance;
    }

    function _swapNativeToLinkAndWrap() internal {
        _swapNativeToLink();
        _wrapAllLinkToOracleVersion();
    }

    function _swapNativeToLink() internal {
        IERC20Upgradeable native = IERC20Upgradeable(nativeToLinkRoute[0]);
        uint256 nativeBalance = native.balanceOf(address(this));

        /* solhint-disable not-rely-on-time */
        uint256[] memory amounts = unirouter.swapExactTokensForTokens(
            nativeBalance,
            0,
            nativeToLinkRoute,
            address(this),
            block.timestamp
        );
        /* solhint-enable not-rely-on-time */
        emit SwappedNativeToLink(block.number, nativeBalance, amounts[amounts.length - 1]);
    }

    function _wrapLinkToOracleVersion(uint256 amount_) internal {
        pegswap.swap(amount_, LINK(), oracleLINK());
    }

    function _wrapAllLinkToOracleVersion() internal {
        _wrapLinkToOracleVersion(balanceOfLink());
    }

    // approve pegswap spending to swap from erc20 link to oracle compatible link
    function _approveLinkSpending() internal {
        address pegswapAddress = address(pegswap);
        IERC20Upgradeable(LINK()).safeApprove(pegswapAddress, 0);
        IERC20Upgradeable(LINK()).safeApprove(pegswapAddress, type(uint256).max);

        IERC20Upgradeable(oracleLINK()).safeApprove(pegswapAddress, 0);
        IERC20Upgradeable(oracleLINK()).safeApprove(pegswapAddress, type(uint256).max);
    }

    function _approveNativeSpending() internal {
        address unirouterAddress = address(unirouter);
        IERC20Upgradeable(NATIVE()).safeApprove(unirouterAddress, 0);
        IERC20Upgradeable(NATIVE()).safeApprove(unirouterAddress, type(uint256).max);
    }

    function _approveSpending() internal {
        _approveNativeSpending();
        _approveLinkSpending();
    }

    /*     */
    /* Set */
    /*     */

    function setUnirouter(address unirouter_) external onlyManager {
        unirouter = IUniswapRouterETH(unirouter_);
    }

    function setShouldSwapToLinkThreshold(uint256 shouldSwapToLinkThreshold_) external onlyManager {
        shouldSwapToLinkThreshold = shouldSwapToLinkThreshold_;
    }

    function setUpkeepId(uint256 upkeepId_) external onlyManager {
        upkeepId = upkeepId_;
    }

    function setNativeToLinkRoute(address[] memory nativeToLinkRoute_) external onlyManager {
        require(nativeToLinkRoute_[0] == NATIVE(), "!NATIVE");
        require(nativeToLinkRoute_[nativeToLinkRoute_.length - 1] == LINK(), "!LINK");
        nativeToLinkRoute = nativeToLinkRoute_;
    }

    /*      */
    /* View */
    /*      */

    /* solhint-disable func-name-mixedcase */
    function NATIVE() public view returns (address link) {
        /* solhint-enable func-name-mixedcase */
        return nativeToLinkRoute[0];
    }

    /* solhint-disable func-name-mixedcase */
    function LINK() public view returns (address link) {
        /* solhint-enable func-name-mixedcase */
        return nativeToLinkRoute[nativeToLinkRoute.length - 1];
    }

    function oracleLINK() public view returns (address link) {
        return oracleLink;
    }

    function balanceOfNative() public view returns (uint256 balance) {
        return IERC20Upgradeable(NATIVE()).balanceOf(address(this));
    }

    function balanceOfLink() public view returns (uint256 balance) {
        return IERC20Upgradeable(LINK()).balanceOf(address(this));
    }

    function balanceOfOracleLink() public view returns (uint256 balance) {
        return IERC20Upgradeable(oracleLINK()).balanceOf(address(this));
    }

    function nativeToLink() external view returns (address[] memory) {
        return nativeToLinkRoute;
    }
}
