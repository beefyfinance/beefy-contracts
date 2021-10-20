// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/common/IUniswapRouterETH.sol";

interface IStrategy_StrategistBuyback {
    function strategist() external view returns (address);
    function setStrategist(address) external;
}

interface IVault_StrategistBuyback {
    function depositAll() external;
    function withdrawAll() external;
    function strategy() external view returns (address);
}

contract StrategistBuyback is OwnableUpgradeable {
    using SafeERC20 for IERC20;

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

    function initialize(
        address _bifiMaxi,
        address _unirouter, 
        address[] memory _nativeToWantRoute
    ) public initializer {
        __Ownable_init();

        bifiMaxi = _bifiMaxi;
        unirouter = _unirouter;

        _setNativeToWantRoute(_nativeToWantRoute);

        IERC20(native).safeApprove(unirouter, type(uint256).max);
        // approve spending by bifiMaxi
        IERC20(native).safeApprove(bifiMaxi, type(uint256).max);
        IERC20(want).safeApprove(bifiMaxi, type(uint256).max);
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
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeBal, 0, nativeToWantRoute, address(this), block.timestamp);

        uint256 wantHarvested = balanceOfWant();
        _depositVaultWantIntoBifiMaxi();

        emit StratHarvest(msg.sender, wantHarvested, balanceOfMooTokens());
    }

    function setVaultStrategist(address _vault, address _newStrategist) external onlyOwner {
        address strategy = address(IVault_StrategistBuyback(_vault).strategy());
        address strategist = IStrategy_StrategistBuyback(strategy).strategist();
        require(strategist == address(this), "Strategist buyback is not the strategist for the target vault");
        IStrategy_StrategistBuyback(strategy).setStrategist(_newStrategist);
    }

    function setUnirouter(address _unirouter) external onlyOwner {
        IERC20(native).safeApprove(_unirouter, type(uint256).max);
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
        IVault_StrategistBuyback(bifiMaxi).depositAll();
    }

    function _withdrawVaultWantFromBifiMaxi() internal {
        IVault_StrategistBuyback(bifiMaxi).withdrawAll();
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