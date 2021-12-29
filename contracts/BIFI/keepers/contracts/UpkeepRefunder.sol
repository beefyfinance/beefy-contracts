// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../interfaces/IPegSwap.sol";
import "../interfaces/IKeeperRegistry.sol";

contract UpkeepRefunder is Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event SwappedNativeToLink(uint256 indexed blockNumber, uint256 nativeAmount, uint256 linkAmount);

    // access control
    mapping (address => bool) private isManager;

    // contracts
    IKeeperRegistry public keeperRegistry;
    IUniswapRouterETH public unirouter;
    IPegSwap public pegswap;

    address[] public nativeToLinkRoute;
    uint256 public shouldSwapToLinkThreshold;
    address public oracleLink;
    uint256 public upkeepId;

    modifier onlyManager() {
        require(msg.sender == owner() || isManager[msg.sender], "!manager");
        _;
    }

    function setManagers(address[] memory _managers, bool _status) external onlyManager {
        for (uint256 managerIndex = 0; managerIndex < _managers.length; managerIndex++) {
            _setManager(_managers[managerIndex], _status);
        }
    }

    function _setManager(address _manager, bool _status) internal {
        isManager[_manager] = _status;
    }

    function initialize (
        address _keeperRegistry,
        address _unirouter,
        address[] memory _nativeToLinkRoute,
        address _oracleLink,
        address _pegswap,
        uint256 _shouldSwapToLinkThreshold
    ) external initializer {
        __Ownable_init();

        keeperRegistry = IKeeperRegistry(_keeperRegistry);
        unirouter = IUniswapRouterETH(_unirouter);
        nativeToLinkRoute = _nativeToLinkRoute;
        oracleLink = _oracleLink;
        pegswap = IPegSwap(_pegswap);
        shouldSwapToLinkThreshold = _shouldSwapToLinkThreshold;

        _approveSpending();
    }

    /*      */
    /* Core */
    /*      */

    /**
     * @dev Harvester needs to approve refunder to allow transfer of tokens. Note that this function has open access control, anyone can refund the upkeep.
     * @return linkRefunded_ amount of link that was refunded to harvester.
     */
    function refundUpkeep(uint256 amount_, uint256 upkeepId_) external returns (uint256 linkRefunded_) {
        require(upkeepId > 0, "Invalid upkeep id.");

        IERC20Upgradeable native = IERC20Upgradeable(NATIVE());
        native.safeTransferFrom(msg.sender, address(this), amount_);

        uint256 linkRefunded;
        if (balanceOfNative() >= shouldSwapToLinkThreshold) {
            linkRefunded = _addHarvestedFundsToUpkeep(upkeepId_);
        }

        return linkRefunded;
    }

    function withdrawAllLink() external onlyManager {
        uint256 amount = IERC20Upgradeable(LINK()).balanceOf(address(this));
        withdrawLink(amount);
    }

    function withdrawLink(uint256 amount) public onlyManager {
        IERC20Upgradeable(LINK()).safeTransfer(msg.sender, amount);
    }

    function wrapAllLinkToOracleVersion() external onlyManager {
        _wrapAllLinkToOracleVersion();
    }

    function unwrapToDexLink(uint256 amount) public onlyManager {
        pegswap.swap(amount, oracleLINK(), LINK());
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
     * @dev Rescues random funds stuck that the strat can't handle.
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
        uint256[] memory amounts = unirouter.swapExactTokensForTokens(nativeBalance, 0, nativeToLinkRoute, address(this), block.timestamp);
        /* solhint-enable not-rely-on-time */
        emit SwappedNativeToLink(block.number, nativeBalance, amounts[amounts.length-1]);
    }

    function _wrapLinkToOracleVersion(uint256 amount) internal {
        pegswap.swap(amount, LINK(), oracleLINK());
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

    function setUnirouter(address newUnirouter) external onlyManager {
        unirouter = IUniswapRouterETH(newUnirouter);
    }

    function setShouldSwapToLinkThreshold(uint256 newThreshold) external onlyManager {
        shouldSwapToLinkThreshold = newThreshold;
    }

    function setNativeToLinkRoute(address[] memory _nativeToLinkRoute) external onlyManager {
        require(_nativeToLinkRoute[0] == NATIVE(), "!NATIVE");
        require(_nativeToLinkRoute[_nativeToLinkRoute.length-1] == LINK(), "!LINK");
        nativeToLinkRoute = _nativeToLinkRoute;
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