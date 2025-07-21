// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IComptroller.sol";
import "../../interfaces/common/IVToken.sol";
import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/ISolidlyRouter.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyMendiezETH is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public iToken;
    address[] public rewards;

    // Third party contracts
    address public comptroller;
    address[] public markets;
    address public wantRouter;

    // Routes
    address[] public outputToNativeRoute;
    ISolidlyRouter.Routes[] public nativeToWantRoute;
    mapping(address => address[]) public rewardToOutputRoutes;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    uint256 public balanceOfPool;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _market,
        address _wantRouter,
        address[] calldata _outputToNativeRoute,
        ISolidlyRouter.Routes[] calldata _nativeToWantRoute,
        CommonAddresses calldata _commonAddresses
    ) external initializer {
        __StratFeeManager_init(_commonAddresses);

        iToken = _market;
        markets.push(_market);
        comptroller = IVToken(_market).comptroller();
        want = IVToken(_market).underlying();
        wantRouter = _wantRouter;

        outputToNativeRoute = _outputToNativeRoute;

        for (uint i; i < _nativeToWantRoute.length; ++i) {
            nativeToWantRoute.push(_nativeToWantRoute[i]);
        }

        output = outputToNativeRoute[0];
        native = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;

        _giveAllowances();
        IComptroller(comptroller).enterMarkets(markets);
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IVToken(iToken).mint(wantBal);
            _updateBalance();
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            uint err = IVToken(iToken).redeemUnderlying(_amount - wantBal);
            require(err == 0, "Error while trying to redeem");
            _updateBalance();
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal * withdrawalFee / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);
        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
        _updateBalance();
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        uint256 beforeBal = balanceOfWant();
        IComptroller(comptroller).claimComp(address(this), markets);
        _swapExtraRewards();
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            _swapRewards();
            uint256 wantHarvested = balanceOfWant() - beforeBal;
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 toNative = IERC20(output).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(
            toNative, 0, outputToNativeRoute, address(this), block.timestamp + 1
        );

        uint256 nativeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    function _swapExtraRewards() internal {
        for (uint i; i < rewards.length; ++i) {
            address reward = rewards[i];
            uint256 rewardBal = IERC20(reward).balanceOf(address(this));
            if (rewardBal > 0) {
                IUniswapRouterETH(unirouter).swapExactTokensForTokens(
                    rewardBal, 0, rewardToOutputRoutes[reward], address(this), block.timestamp + 1
                );
            }
        }
    }

    function _swapRewards() internal {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        ISolidlyRouter(wantRouter).swapExactTokensForTokens(
            nativeBal, 0, nativeToWantRoute, address(this), block.timestamp
        );
    }

    function _updateBalance() internal {
        balanceOfPool = IVToken(iToken).balanceOfUnderlying(address(this));
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool;
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public returns (uint256) {
        IComptroller(comptroller).claimComp(address(this), markets);
        return IERC20(output).balanceOf(address(this));
    }

    // native reward amount for calling harvest
    function callReward() public returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            uint256[] memory amountsOut = IUniswapRouterETH(unirouter).getAmountsOut(
                outputBal, outputToNativeRoute
            );
            nativeOut = amountsOut[amountsOut.length - 1];
        }

        return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            super.setWithdrawalFee(0);
        } else {
            super.setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        uint err = IVToken(iToken).redeem(IERC20(iToken).balanceOf(address(this)));
        require(err == 0, "Error while trying to redeem");
        _updateBalance();

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        uint err = IVToken(iToken).redeem(IERC20(iToken).balanceOf(address(this)));
        require(err == 0, "Error while trying to redeem");
        _updateBalance();

        pause();
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(iToken, type(uint256).max);
        IERC20(output).safeApprove(unirouter, type(uint256).max);
        IERC20(native).safeApprove(wantRouter, type(uint256).max);

        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, type(uint256).max);
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(iToken, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(wantRouter, 0);

        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
        }
    }

    function setRewards(address[] calldata _rewardToOutputRoute) external onlyOwner {
        address _reward = _rewardToOutputRoute[0];
        address _output = _rewardToOutputRoute[_rewardToOutputRoute.length - 1];

        require(_reward != want, "reward==want");
        require(_reward != iToken, "reward==iToken");
        require(_output != output, "reward==output");

        rewards.push(_reward);
        rewardToOutputRoutes[_reward] = _rewardToOutputRoute;

        IERC20(_reward).safeApprove(unirouter, type(uint256).max);
    }

    function resetRewards() external onlyManager {
        for (uint i; i < rewards.length; ++i) {
            address reward = rewards[i];
            IERC20(reward).safeApprove(unirouter, 0);
            delete rewardToOutputRoutes[reward];
        }

        delete rewards;
    }

    function setWantRouter(address _wantRouter) external onlyOwner {
        IERC20(native).safeApprove(wantRouter, 0);
        wantRouter = _wantRouter;
        if (!paused()) IERC20(native).safeApprove(_wantRouter, type(uint256).max);
    }

    function _solidlyToRoute(ISolidlyRouter.Routes[] memory _route) internal pure returns (address[] memory) {
        address[] memory route = new address[](_route.length + 1);
        route[0] = _route[0].from;
        for (uint i; i < _route.length; ++i) {
            route[i + 1] = _route[i].to;
        }
        return route;
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function nativeToWant() external view returns (address[] memory) {
        ISolidlyRouter.Routes[] memory _route = nativeToWantRoute;
        return _solidlyToRoute(_route);
    }

    function rewardToOutput(uint _id) external view returns (address[] memory) {
        return rewardToOutputRoutes[rewards[_id]];
    }

    receive() external payable {
        IWrappedNative(native).deposit{value: msg.value}();
    }
}