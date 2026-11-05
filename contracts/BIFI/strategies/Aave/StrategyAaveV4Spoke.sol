// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../interfaces/aave/IAaveV4Spoke.sol";
import "../../interfaces/merkl/IMerklClaimer.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

/// @notice Supplies a single reserve through an existing Aave V4 Spoke, without borrowing.
/// @dev New deployments only. Supplied shares live in the Spoke, not an ERC20 receipt token.
contract StrategyAaveV4Spoke is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IAaveV4Spoke public spoke;
    IAaveV4Hub public hub;
    uint256 public reserveId;
    uint256 public assetId;
    IMerklClaimer public claimer;
    uint256 public storedBalance;

    event SetHarvestOnDeposit(bool enabled);
    event SetLockDuration(uint256 duration);
    event SetClaimer(address claimer);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _spoke,
        uint256 _reserveId,
        address _claimer,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) external initializer {
        spoke = IAaveV4Spoke(_spoke);
        reserveId = _reserveId;
        IAaveV4Spoke.Reserve memory reserve = spoke.getReserve(reserveId);
        require(reserve.underlying == _addresses.want, "!want");
        require(address(reserve.hub).code.length > 0, "!hub");
        hub = reserve.hub;
        assetId = reserve.assetId;

        __BaseStrategy_init(_addresses, _rewards);
        // The shared harvest routine treats all native tokens as rewards, including idle balances.
        require(want != native, "!nativeWant");
        setClaimer(_claimer);
        setHarvestOnDeposit(_harvestOnDeposit);
    }

    function stratName() public pure override returns (string memory) {
        return "AaveV4Spoke";
    }

    /// @notice Unharvested interest is excluded; losses and share rounding are reflected immediately.
    function balanceOfPool() public view override returns (uint256) {
        uint256 supplied = spoke.getUserSuppliedAssets(reserveId, address(this));
        return supplied < storedBalance ? supplied : storedBalance;
    }

    function balanceOf() public view override returns (uint256) {
        uint256 balance = balanceOfWant() + balanceOfPool();
        uint256 locked = lockedProfit();
        return balance > locked ? balance - locked : 0;
    }

    function _deposit(uint256 amount) internal override {
        storedBalance = balanceOfPool();
        // Aave floors minted shares; keep atomic dust idle so deposit and harvest remain callable.
        if (hub.previewAddByAssets(assetId, amount) == 0) return;
        IERC20(want).forceApprove(address(spoke), amount);
        (uint256 shares,) = spoke.supply(reserveId, amount, address(this));
        require(shares > 0, "!shares");
        // Supply rounds shares down. Do not account the unrecoverable rounding dust as principal.
        storedBalance += hub.previewRemoveByShares(assetId, shares);
    }

    function _withdraw(uint256 amount) internal override {
        if (amount == 0) return;
        (, uint256 withdrawn) = spoke.withdraw(reserveId, amount, address(this));
        storedBalance = withdrawn < storedBalance ? storedBalance - withdrawn : 0;
        // Withdraw rounds burned shares up, potentially consuming one extra unit of principal.
        storedBalance = balanceOfPool();
    }

    function _emergencyWithdraw() internal override {
        if (spoke.getUserSuppliedShares(reserveId, address(this)) > 0) {
            spoke.withdraw(reserveId, type(uint256).max, address(this));
        }
        storedBalance = 0;
    }

    // Merkl proofs are supplied externally; harvesting does not fetch or submit them.
    function _claim() internal override {}

    function _swapRewardsToNative() internal override {
        uint256 supplied = spoke.getUserSuppliedAssets(reserveId, address(this));
        if (supplied > storedBalance) {
            uint256 interest = supplied - storedBalance;
            if (interest > minAmounts[want]) {
                (, uint256 withdrawn) = spoke.withdraw(reserveId, interest, address(this));
                storedBalance = balanceOfPool();
                _swap(want, native, withdrawn);
            }
        } else {
            storedBalance = supplied;
        }
        super._swapRewardsToNative();
    }

    function _verifyRewardToken(address token) internal view override {
        require(token != address(spoke) && token != address(hub), "!reward");
    }

    /// @notice Anyone may submit valid proofs, but the recipient is always this strategy.
    /// @dev This converts received want into harvestable rewards, but cannot prevent direct distributor claims.
    function claim(address[] calldata tokens, uint256[] calldata amounts, bytes32[][] calldata proofs) external {
        require(tokens.length == amounts.length && tokens.length == proofs.length, "!length");
        uint256 beforeBal = balanceOfWant();
        address[] memory users = new address[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            users[i] = address(this);
        }
        claimer.claim(users, tokens, amounts, proofs);
        _swap(want, native, balanceOfWant() - beforeBal);
    }

    function setClaimer(address _claimer) public onlyManager {
        require(_claimer.code.length > 0, "!claimer");
        claimer = IMerklClaimer(_claimer);
        emit SetClaimer(_claimer);
    }

    function setHarvestOnDeposit(bool enabled) public override onlyManager {
        harvestOnDeposit = enabled;
        emit SetHarvestOnDeposit(enabled);
    }

    function setLockDuration(uint256 duration) external override onlyManager {
        require(duration > 0 && duration <= 7 days, "!duration");
        // Checkpoint the remaining profit before changing the schedule; never unlock it instantly.
        totalLocked = lockedProfit();
        lastHarvest = block.timestamp;
        lockDuration = duration;
        emit SetLockDuration(duration);
    }
}
