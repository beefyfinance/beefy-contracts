// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/stargate/IStargateChef.sol";
import "../../interfaces/stargate/IStargateRouter.sol";
import "../../interfaces/stargate/IStargateRouterETH.sol";
import "../../interfaces/stargate/IStargatePool.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "./StrategyCore.sol";

contract StrategyStargateMulti is StrategyCore {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    // Tokens used
    address public lpToken;
    address[] public rewards;

    // Third party contracts
    address public chef;
    uint256 public poolId;
    address public unirouter;
    address public stargateRouter;
    uint256 public routerPoolId;

    // Routes
    mapping(address => mapping(address => address[])) public routes;
    mapping(address => uint256) public minToSwap;

    bool public outputIsSTG;

    function initialize(
        address _native,
        uint256 _poolId,
        address _chef,
        address _unirouter,
        address _stargateRouter,
        uint256 _routerPoolId,
        uint256 _minToSwap,
        bool _outputIsSTG,
        address[] calldata _outputToWantRoute,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratManager_init(_commonAddresses);
        native = IERC20Upgradeable(_native);
        poolId = _poolId;
        chef = _chef;
        unirouter = _unirouter;
        stargateRouter = _stargateRouter;
        routerPoolId = _routerPoolId;

        output = IERC20Upgradeable(_outputToWantRoute[0]);
        want = IERC20Upgradeable(_outputToWantRoute[_outputToWantRoute.length - 1]);
        routes[address(output)][address(want)] = _outputToWantRoute;

        minToSwap[address(output)] = _minToSwap;
        outputIsSTG = _outputIsSTG;

        _giveAllowances();
    }

    /**
     * @dev Helper function to deposit to the underlying platform.
     * @param _amount The amount to deposit.
     */
    function _depositUnderlying(uint256 _amount) internal override {
        if (want != native) {
            IStargateRouter(stargateRouter).addLiquidity(routerPoolId, _amount, address(this));
        } else {
            IWrappedNative(address(native)).withdraw(_amount);
            _amount = address(this).balance;
            IStargateRouter(stargateRouter).addLiquidityETH{value: _amount}();
        }

        uint256 lpBal = IERC20Upgradeable(lpToken).balanceOf(address(this));
        if (lpBal > 0) {
            IStargateChef(chef).deposit(poolId, lpBal);
        }
        emit DepositUnderlying(_amount);
    }

    /**
     * @dev Helper function to withdraw from the underlying platform.
     * @param _amount The amount to withdraw.
     */
    function _withdrawUnderlying(uint256 _amount) internal override {
        uint256 lpAmount = _wantToLp(_amount);
        if (lpAmount > balanceOfLp()) {
            lpAmount = balanceOfLp();
        }

        IStargateChef(chef).withdraw(poolId, lpAmount);
        IStargateRouter(stargateRouter).instantRedeemLocal(
            uint16(routerPoolId),
            lpAmount,
            address(this)
        );
        if (want == native) {
            uint256 toWrap = address(this).balance;
            IWrappedNative(address(native)).deposit{value: toWrap}();
        }
        emit WithdrawUnderlying(_amount);
    }

    /**
     * @dev It calculates the invested balance of 'want' in the underlying platform.
     * @return balanceOfPool The invested balance of the wanted asset.
     */
    function balanceOfPool() public override view returns (uint256) {
        return _lpToWant(balanceOfLp());
    }

    /**
     * @dev It returns the balance of LP tokens invested in the staking contract.
     * @return balanceOfLp The invested balance of the LP tokens.
     */
    function balanceOfLp() public view returns (uint256) {
        (uint256 amount,) = IStargateChef(chef).userInfo(poolId, address(this));
        return amount;
    }

    /**
     * @dev It returns the amount of want tokens you would receive from withdrawing from the LP.
     * @return lpToWant The amount of want tokens that could be withdrawn from LP tokens.
     */
    function _lpToWant(uint _amountLP) internal view returns (uint) {
        return IStargatePool(lpToken).amountLPtoLD(_amountLP);
    }

    /**
     * @dev It returns the amount of LP tokens you would receive from depositing want tokens.
     * @return lpToWant The amount of LP tokens from the number of want tokens.
     */
    function _wantToLp(uint _amountLD) internal view returns (uint) {
        require(IStargatePool(lpToken).totalLiquidity() > 0);
        uint256 _amountSD = _amountLD / IStargatePool(lpToken).convertRate();
        return _amountSD 
            * IStargatePool(lpToken).totalSupply() 
            / IStargatePool(lpToken).totalLiquidity();
    }

    /**
     * @dev It claims rewards from the underlying platform and converts any extra rewards back into
     * the output token.
     */
    function _getRewards() internal override {
        IStargateChef(chef).deposit(poolId, 0);
        uint256 rewardLength = rewards.length;
        for (uint256 i; i < rewardLength;) {
            _swap(rewards[i], address(output), IERC20Upgradeable(rewards[i]).balanceOf(address(this)));
            unchecked { ++i; }
        }
    }

    /**
     * @dev It converts the output to the want asset, in this case it swaps half for each LP token
     * and adds liquidity.
     */
    function _convertToWant() internal override {
        _swap(address(output), address(want), output.balanceOf(address(this)));
    }

    /**
     * @dev It swaps from one token to another.
     * @param _fromToken The token to swap from.
     * @param _toToken The token to swap to.
     */
    function _swap(
        address _fromToken,
        address _toToken,
        uint256 _amount
    ) internal {
        if (_fromToken == _toToken) {
            return;
        }
        
        if (_amount > minToSwap[_fromToken]) {
            address[] memory path = routes[_fromToken][_toToken];
            require(path[0] != address(0), "path not set");
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(
                _amount, 0, path, address(this), block.timestamp
            );
        }
    }

    /**
     * @dev It calculates the output reward available to the strategy by calling the pending
     * rewards function on the underlying platform.
     * @return rewardsAvailable The amount of output rewards not yet harvested.
     */
    function rewardsAvailable() public override view returns (uint256) {
        if (outputIsSTG){
            return IStargateChef(chef).pendingStargate(poolId, address(this));
        } else {
            return IStargateChef(chef).pendingEmissionToken(poolId, address(this));
        }
    }

    /**
     * @dev It withdraws from the underlying platform without caring about rewards.
     */
    function _emergencyWithdraw() internal override {
        IStargateChef(chef).emergencyWithdraw(poolId);
    }

    /**
     * @dev It gives allowances to the required addresses.
     */
    function _giveAllowances() internal override {
        want.safeApprove(stargateRouter, type(uint).max);
        IERC20Upgradeable(lpToken).safeApprove(chef, type(uint).max);
        output.safeApprove(unirouter, type(uint).max);

        for (uint i; i < rewards.length;) {
            IERC20Upgradeable(rewards[i]).safeApprove(unirouter, type(uint).max);
            unchecked { ++i; }
        }
    }

    /**
     * @dev It revokes allowances from the previously approved addresses.
     */
    function _removeAllowances() internal override {
        want.safeApprove(stargateRouter, 0);
        IERC20Upgradeable(lpToken).safeApprove(chef, 0);
        output.safeApprove(unirouter, 0);

        for (uint i; i < rewards.length;) {
            IERC20Upgradeable(rewards[i]).safeApprove(unirouter, 0);
            unchecked { ++i; }
        }
    }

    /**
     * @dev Helper function to view the token route for swapping between output and want.
     * @return outputToWantRoute The token route between output to want.
     */
    function outputToWant() external override view returns (address[] memory) {
        return routes[address(output)][address(want)];
    }

    /**
     * @dev It notifies the strategy that there is an extra token to compound back into the output.
     * @param _route The route for the extra reward token.
     */
    function addReward(address[] calldata _route, uint256 _minToSwap) external atLeastRole(ADMIN) {
        address fromToken = _route[0];
        address toToken = _route[_route.length - 1];
        require(fromToken != address(want) && fromToken != address(lpToken), "want is not a reward");
        require(toToken == address(output), "dest token is not output");

        rewards.push(fromToken);
        routes[fromToken][toToken] = _route;
        minToSwap[fromToken] = _minToSwap;

        IERC20Upgradeable(fromToken).safeApprove(unirouter, 0);
        IERC20Upgradeable(fromToken).safeApprove(unirouter, type(uint).max);
    }

    /**
     * @dev It removes the extra reward previously added by the owner.
     */
    function removeReward() external atLeastRole(STRATEGIST) {
        address token = rewards[rewards.length - 1];
        IERC20Upgradeable(token).safeApprove(unirouter, 0);
        rewards.pop();
    }
}
