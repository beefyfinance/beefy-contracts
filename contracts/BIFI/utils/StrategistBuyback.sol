// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/common/IUniswapRouterETH.sol";
import "../interfaces/beefy/IVault.sol";
import "../interfaces/beefy/IStrategyComplete.sol";

contract StrategistBuyback is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public want;

    address public bifiMaxi;
    address public unirouter;

    address[] public nativeToWantRoute;

    address[] public trackedVaults;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 mooTokenBalance);
    event WithdrawToken(address indexed token, uint256 amount);
    event TrackingVault(address indexed vaultAddress);
    event UntrackingVault(address indexed vaultAddress);

    constructor(
        address _bifiMaxi,
        address _unirouter, 
        address[] memory _nativeToWantRoute
    ) public {
        bifiMaxi = _bifiMaxi;
        unirouter = _unirouter;

        _setNativeToWantRoute(_nativeToWantRoute);

        IERC20(native).safeApprove(unirouter, uint256(-1));
        // approve spending by bifiMaxi
        IERC20(native).safeApprove(bifiMaxi, uint256(-1));
        IERC20(want).safeApprove(bifiMaxi, uint256(-1));
    }

    function depositVaultWantIntoBifiMaxi() external onlyOwner {
        _depositVaultWantIntoBifiMaxi();
    }

    function withdrawVaultWantFromBifiMaxi() external onlyOwner {
        _withdrawVaultWantFromBifiMaxi();
    }

    // Convert and send to beefy maxi
    function harvest() public {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeBal, 0, nativeToWantRoute, address(this), now);

        uint256 wantHarvested = balanceOfWant();
        _depositVaultWantIntoBifiMaxi();

        emit StratHarvest(msg.sender, wantHarvested, balanceOfMooTokens());
    }

    function setVaultStrategist(address _vault, address _newStrategist) external onlyOwner {
        address strategy = address(IVault(_vault).strategy());
        address strategist = IStrategyComplete(strategy).strategist();
        require(strategist == address(this), "Strategist buyback is not the strategist for the target vault");
        IStrategyComplete(strategy).setStrategist(_newStrategist);
    }

    function setUnirouter(address _unirouter) external onlyOwner {
        IERC20(native).safeApprove(_unirouter, uint256(-1));
        IERC20(native).safeApprove(unirouter, 0);

        unirouter = _unirouter;
    }

    function setNativeToWantRoute(address[] memory _route) external onlyOwner {
        _setNativeToWantRoute(_route);
    }
    
    function withdrawToken(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);

        emit WithdrawToken(_token, amount);
    }

    function _depositVaultWantIntoBifiMaxi() internal {
        IVault(bifiMaxi).depositAll();
    }

    function _withdrawVaultWantFromBifiMaxi() internal {
        IVault(bifiMaxi).withdrawAll();
    }

    function _setNativeToWantRoute(address[] memory _route) internal {
        native = _route[0];
        want = _route[_route.length - 1];
        nativeToWantRoute = _route;
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfMooTokens() public view returns (uint256) {
        return IERC20(bifiMaxi).balanceOf(address(this));
    }

    function trackVault(address _vaultAddress) external onlyOwner {
        trackedVaults.push(_vaultAddress);
        emit TrackingVault(_vaultAddress);
    }

    function untrackVault(address _vaultAddress) external onlyOwner {
        require(trackedVaults.length > 0, "No vaults are being tracked.");
        uint256 foundVaultIndex;
        bool didFindVault;

        // find vault
        for (uint256 index; index < trackedVaults.length; ++index) {
            if (trackedVaults[index] == _vaultAddress) {
                didFindVault = true;
                foundVaultIndex = index;
                break;
            }
        }

        require(didFindVault == true, "Vault is not being tracked.");

        // make address at found index the address at last index, then pop last index.
        uint256 lastVaultIndex = trackedVaults.length - 1;
        trackedVaults[foundVaultIndex] = trackedVaults[lastVaultIndex];
        trackedVaults.pop();

        emit UntrackingVault(_vaultAddress);
    }
}