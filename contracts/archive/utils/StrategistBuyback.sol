// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
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

interface IERC20_StrategistBuyback {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}


contract StrategistBuyback is OwnableUpgradeable {
    // Tokens used
    address public native;
    address public want;

    address public bifiMaxi;
    address public unirouter;

    address[] public nativeToWantRoute;

    address[] public trackedVaults; // 1 indexed due to mapping having default value of 0.
    mapping(address => uint256) public trackedVaultsArrayIndex; // there will be dummy vault at index 0

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

        IERC20_StrategistBuyback(native).approve(unirouter, type(uint256).max);
        // approve spending by bifiMaxi
        IERC20_StrategistBuyback(native).approve(bifiMaxi, type(uint256).max);
        IERC20_StrategistBuyback(want).approve(bifiMaxi, type(uint256).max);

        trackVault(address(0)); // dummy vault to overcome issue where mapping values are defaulted to 0;
    }

    function depositVaultWantIntoBifiMaxi() external onlyOwner {
        _depositVaultWantIntoBifiMaxi();
    }

    function withdrawVaultWantFromBifiMaxi() external onlyOwner {
        _withdrawVaultWantFromBifiMaxi();
    }

    // Convert and send to beefy maxi
    function harvest() public {
        uint256 nativeBal = IERC20_StrategistBuyback(native).balanceOf(address(this));
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
        IERC20_StrategistBuyback(native).approve(_unirouter, type(uint256).max);
        IERC20_StrategistBuyback(native).approve(unirouter, 0);

        unirouter = _unirouter;
    }

    function setNativeToWantRoute(address[] memory _route) external onlyOwner {
        _setNativeToWantRoute(_route);
    }
    
    function withdrawToken(address _token) external onlyOwner {
        uint256 amount = IERC20_StrategistBuyback(_token).balanceOf(address(this));
        IERC20_StrategistBuyback(_token).transfer(msg.sender, amount);

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
        return IERC20_StrategistBuyback(want).balanceOf(address(this));
    }

    function balanceOfMooTokens() public view returns (uint256) {
        return IERC20_StrategistBuyback(bifiMaxi).balanceOf(address(this));
    }

    function trackVault(address _vaultAddress) public onlyOwner {
        trackedVaults.push(_vaultAddress);
        trackedVaultsArrayIndex[_vaultAddress] = trackedVaults.length - 1; // new vault will have last index of 
        emit TrackingVault(_vaultAddress);
    }

    function untrackVault(address _vaultAddress) external onlyOwner {
        require(trackedVaults.length > 1, "No vaults are being tracked.");
        uint256 foundVaultIndex = trackedVaultsArrayIndex[_vaultAddress];

        require(foundVaultIndex > 0, "Vault is not being tracked.");

        // make address at found index the address at last index, then pop last index.
        uint256 lastVaultIndex = trackedVaults.length - 1;

        address lastVaultAddress = trackedVaults[lastVaultIndex];
        // make vault to untrack point to 0 index (not tracked).
        trackedVaultsArrayIndex[_vaultAddress] = 0;
        // fix mapping so that the address of last vault index to now points to removed vault index.
        trackedVaultsArrayIndex[lastVaultAddress] = foundVaultIndex;
        // make remove vault index point to the last vault, as its taken its spot.
        trackedVaults[foundVaultIndex] = lastVaultAddress;
        trackedVaults.pop();

        emit UntrackingVault(_vaultAddress);
    }
}