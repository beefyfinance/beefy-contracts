// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/kyber/IKyberFairLaunch.sol";
import "../../interfaces/kyber/IDMMRouter.sol";
import "../../interfaces/kyber/IDMMPool.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../../utils/Path.sol";
import "../../utils/UniV3Actions.sol";


contract StrategyKyberLP is StratFeeManagerInitializable {
    using Path for bytes;
    using SafeERC20 for IERC20;

    // Tokens used
    address public want;
    address public output;
    address public native;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public chef;
    uint256 public pid;
    address public elasticRouter;
    address public quoter;

    struct Reward {
        address[] rewardPath;
        address[] rewardToNativeRoute; // DMM Router route
        bytes rewardToNativePath; // elastic router path
        bool useElastic; // Should we use elastic router
        uint256 minAmount; 
    }

    // Mapping is Reward Token to Reward Struct
    mapping(address => Reward) public rewards;
    address[] public rewardTokens;

    address[] public outputToNativeRoute;
    address[] public nativeToLp0Route;
    address[] public nativeToLp1Route;
   
   // Use elastic router
    bytes public outputToNativePath;
    bytes public nativeToLp0Path;
    bytes public nativeToLp1Path;
   
    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 indexed wantHarvested, uint256 indexed tvl);
    event Deposit(uint256 indexed tvl);
    event Withdraw(uint256 indexed tvl);
    event ChargedFees(uint256 indexed callFees, uint256 indexed beefyFees, uint256 indexed strategistFees);

    function initialize(
        address _want,
        address _chef, 
        address _elasticRouter,
        address _quoter,
        uint256 _pid,
        bytes[] calldata _paths,
        CommonAddresses calldata _commonAddresses
    ) public initializer  {
        __StratFeeManager_init(_commonAddresses);

        want = _want;
        chef = _chef;
        elasticRouter = _elasticRouter;
        quoter = _quoter;
        pid = _pid;

        outputToNativeRoute = pathToRoute(_paths[0]);
        nativeToLp0Route = pathToRoute(_paths[1]);
        nativeToLp1Route = pathToRoute(_paths[2]);

        outputToNativePath = _paths[0];
        nativeToLp0Path = _paths[1];
        nativeToLp1Path = _paths[2];

        native = nativeToLp0Route[0];
        output = outputToNativeRoute[0];
        lpToken0 = nativeToLp0Route[nativeToLp0Route.length - 1];
        lpToken1 = nativeToLp1Route[nativeToLp1Route.length - 1];

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IKyberFairLaunch(chef).deposit(pid, wantBal, true);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IKyberFairLaunch(chef).withdraw(pid, _amount - wantBal);
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = (wantBal * withdrawalFee) / WITHDRAWAL_MAX;
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
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IKyberFairLaunch(chef).harvest(pid);
        swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function swapRewardsToNative() internal {
       uint256 nativeBal = address(this).balance;
       if (nativeBal > 0) {
            IWrappedNative(native).deposit{value: nativeBal}();
        }

        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            if (outputToNativePath.length > 0) {
                UniV3Actions.kyberSwap(elasticRouter, outputToNativePath, outputBal);
            }
        }
        // extras
        for (uint i; i < rewardTokens.length;) {
            uint bal = IERC20(rewardTokens[i]).balanceOf(address(this));
            if (bal >= rewards[rewardTokens[i]].minAmount) {
                if (rewards[rewardTokens[i]].useElastic) {
                    UniV3Actions.kyberSwap(elasticRouter, rewards[rewardTokens[i]].rewardToNativePath, bal);
                } else {
                    uint256 len = rewards[rewardTokens[i]].rewardToNativeRoute.length;
                    IERC20[] memory route = new IERC20[](len);
                    for (uint j; j < len; j++) {
                        route[j] = IERC20(rewards[rewardTokens[i]].rewardToNativeRoute[j]);
                    }
                     IDMMRouter(unirouter).swapExactTokensForTokens(
                        bal,
                        0,
                        rewards[rewardTokens[i]].rewardPath,
                        route,
                        address(this),
                        block.timestamp
                    );
                }
            }
            unchecked {
                ++i;
            }
        }
    }
    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        uint256 lp0Amt = nativeBal / 2;
        uint256 lp1Amt = nativeBal - lp0Amt;

        uint256 lp0Decimals = 10**IERC20Extended(lpToken0).decimals();
        uint256 lp1Decimals = 10**IERC20Extended(lpToken1).decimals();
        uint256 out0 = getAmountOut(nativeToLp0Path, lp0Amt);
        uint256 out1 = getAmountOut(nativeToLp1Path, lp1Amt);
        (uint256 reserveA, uint256 reserveB) = IDMMPool(want).getReserves();
        uint256 amountB = IDMMRouter(unirouter).quote(out0, reserveA, reserveB);
        out0 = out0 * 1e18 / lp0Decimals;
        out1 = out1 * 1e18 / lp1Decimals;
        amountB = amountB * 1e18 / lp1Decimals;
        uint256 ratio = ((out0 * 1e18) * out1) / amountB / out0;
        lp1Amt = nativeBal * 1e18 / (ratio + 1e18);
        lp0Amt = nativeBal - lp1Amt;
        

        if (lpToken0 != native) {
            UniV3Actions.kyberSwap(elasticRouter, nativeToLp0Path, lp0Amt);
        }

        if (lpToken1 != native) {
            UniV3Actions.kyberSwap(elasticRouter, nativeToLp1Path, lp1Amt);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        uint256[2] memory bounds = [0, type(uint).max];
        IDMMRouter(unirouter).addLiquidity(lpToken0, lpToken1, want, lp0Bal, lp1Bal, 1, 1, bounds, address(this), block.timestamp);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256 amount) {
        (amount,,) = IKyberFairLaunch(chef).getUserInfo(pid, address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256[] memory amounts) {
         return IKyberFairLaunch(chef).pendingRewards(pid, address(this));
    }

    // native reward amount for calling harvest
    function callReward() public pure returns (uint256) {
        return 0; // multiple swap providers with no easy way to estimate native output.
    }

    function addRewardToken(address _token, Reward calldata _reward) external onlyOwner {
        require(_token != want, "!want");
        require(_token != native, "!native");
        if (_reward.rewardToNativeRoute[0] != address(0)) {
            IERC20(_token).safeApprove(unirouter, 0);
            IERC20(_token).safeApprove(unirouter, type(uint).max);
        } else {
            IERC20(_token).safeApprove(elasticRouter, 0);
            IERC20(_token).safeApprove(elasticRouter, type(uint).max);
        }

        rewards[_token] = _reward;
        rewardTokens.push(_token);
    }

    function resetRewardTokens() external onlyManager {
        for (uint i; i < rewardTokens.length;) {
            delete rewards[rewardTokens[i]];
        unchecked { ++i; }
        }
        delete rewardTokens;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IKyberFairLaunch(chef).emergencyWithdraw(pid);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IKyberFairLaunch(chef).emergencyWithdraw(pid);
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
        IERC20(want).safeApprove(chef, type(uint).max);
        IERC20(output).safeApprove(elasticRouter, type(uint).max);
        IERC20(native).safeApprove(elasticRouter, type(uint).max);
      
        if (rewardTokens.length != 0) {
            for (uint i; i < rewardTokens.length; ++i) {
                if (rewards[rewardTokens[i]].rewardToNativeRoute[0] != address(0)) {
                    IERC20(rewardTokens[i]).safeApprove(unirouter, 0);
                    IERC20(rewardTokens[i]).safeApprove(unirouter, type(uint).max);
                } else {
                    IERC20(rewardTokens[i]).safeApprove(elasticRouter, 0);
                    IERC20(rewardTokens[i]).safeApprove(elasticRouter, type(uint).max);
                }
            }
        }

        
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, type(uint).max);

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(elasticRouter, 0);
        IERC20(native).safeApprove(elasticRouter, 0);
  
        if (rewardTokens.length != 0) {
            for (uint i; i < rewardTokens.length; ++i) {
                if (rewards[rewardTokens[i]].rewardToNativeRoute[0] != address(0)) {
                    IERC20(rewardTokens[i]).safeApprove(unirouter, 0);
                } else {
                    IERC20(rewardTokens[i]).safeApprove(elasticRouter, 0);
                }
            }
        }

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }

    function pathToRoute(bytes memory _path) public pure returns (address[] memory) {
        uint numPools = _path.numPools();
        address[] memory route = new address[](numPools + 1);
        for (uint i; i < numPools; i++) {
            (address tokenA, address tokenB,) = _path.decodeFirstPool();
            route[i] = tokenA;
            route[i + 1] = tokenB;
            _path = _path.skipToken();
        }
        return route;
    }

    function getAmountOut(bytes memory path, uint256 amount) internal returns (uint256 amountOut) {
        (bool success, bytes memory data) = quoter.call(abi.encodeWithSignature("quoteExactInput(bytes,uint256)", path, amount));
        require(success == true, "Staticcall fail");
        (amountOut, ,,) = abi.decode(data, (uint256,uint160[],uint32[],uint256));
    }

      receive () external payable {}
}