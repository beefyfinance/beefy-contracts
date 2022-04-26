// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/ITridentRouter.sol";
import "../../interfaces/common/IMasterChef.sol";
import "../../interfaces/stargate/IStargateRouter.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";
import "../../utils/StringUtils.sol";
import "../../utils/GasThrottler.sol";

abstract contract StrategyTridentRouter {
    // Routes
    address[][] public outputToNativeRoute;
    address[][] public outputToLp0Route;
    address[] public outputToNativePoolRoute;
    address[] public outputToLp0PoolRoute;

    // paths
    ITridentRouter.Path[] public outputToNativePath;
    ITridentRouter.Path[] public outputToLp0Path;

    // address
    address private unirouter; // private scope to prevent clash with unirouter var in StratManager

    constructor(
        address _unirouter,
        address[][] memory _outputToNativeRoute, // [[output,tokenX],[tokenX,tokenY],[tokenY,native]]
        address[][] memory _outputToLp0Route, // [[output,tokenX],[tokenX,tokenY],[tokenY,Lp0]]
        address[] memory _outputToNativePoolRoute, // [pool_with_output, ..., pool_with_native]
        address[] memory _outputToLp0PoolRoute // [pool_with_output, ..., pool_with_lp0]
    ) public {
        //// Native routing 
        outputToNativePoolRoute = _outputToNativePoolRoute;
        outputToNativeRoute = _outputToNativeRoute;
        unirouter = _unirouter;
        
        // Setup Native "path" object required by exactInput
        for (uint256 i; i < outputToNativePoolRoute.length - 1; ) {
            outputToNativePath.push(ITridentRouter.Path(
                // path of pool
                outputToNativePoolRoute[i], 
                // user data used by pool (tokenIN,recipient,unwrapBento) 
                // pool `N` should transfer its output tokens to pool `N+1` directly.
                abi.encode(outputToNativeRoute[i][0], outputToNativePoolRoute[i+1], true) 
            )); 
            ++i;
        }
        // The last pool should transfer its output tokens to the user.
        outputToNativePath.push(ITridentRouter.Path(
            // pool address
            outputToNativePoolRoute[outputToNativePoolRoute.length - 1], 
            // user data used by pool (tokenIN, recipient, unwrapBento) 
            // last pool should transfer to user address(this)
            abi.encode(outputToNativeRoute[outputToNativePoolRoute.length - 1][0], address(this), true)
            ));
        //
        
        //// LP routing 
        outputToLp0PoolRoute = _outputToLp0PoolRoute;
        outputToLp0Route = _outputToLp0Route;
        

        // Setup Native "path" object required by exactInput
        for (uint256 i; i < outputToLp0PoolRoute.length - 1; ) {
            outputToLp0Path.push(ITridentRouter.Path(
                // pool address
                outputToLp0PoolRoute[i], 
                // user data used by pool (tokenIN,recipient,unwrapBento) 
                // pool `N` should transfer its output tokens to pool `N+1` directly.
                abi.encode(outputToLp0Route[i][0], outputToLp0PoolRoute[i+1], true) 
                // NB unwrap bento might be false for all except last trade
            )); 
            ++i;
        }
        // The last pool should transfer its output tokens to the user.
        outputToLp0Path.push(ITridentRouter.Path(
            // pool address
            outputToLp0PoolRoute[outputToLp0PoolRoute.length - 1], 
            // user data used by pool (tokenIN, recipient, unwrapBento) 
            // last pool should transfer to user address(this)
            abi.encode(outputToLp0Route[outputToLp0PoolRoute.length - 1][0], address(this), true)
            ));
    }

    // swap tokens 
    // @dev Ensure pools are tristed before calling this function
    function tridentSwap(address _tokenIn, uint256 _amountIn, ITridentRouter.Path[] memory _path) internal {
        ITridentRouter.ExactInputParams memory exactInputParams = ITridentRouter.ExactInputParams(_tokenIn, _amountIn, 0, _path);
        ITridentRouter(unirouter).exactInput(exactInputParams);
    }
}

contract StrategyStargateStakingTridentRouter is StratManager, FeeManager, GasThrottler, StrategyTridentRouter {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public lpToken0;

    // Third party contracts
    address public chef;
    uint256 public poolId;
    address public stargateRouter;
    uint256 public routerPoolId;
    address public bento;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    string public pendingRewardsFunctionName;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        uint256[] memory _poolIdAndRouterPoolId,
        address _chef,
        address _vault,
        address[] memory _unirouterAndStargateRouter,
        address _strategist,
        address[] memory _beefyFeeRecipientAndKeeper,
        address[][] memory _outputToNativeRoute, 
        address[][] memory _outputToLp0Route, 
        address[] memory _outputToNativePoolRoute, 
        address[] memory _outputToLp0PoolRoute 
    ) StratManager(
        _beefyFeeRecipientAndKeeper[1], _strategist, _unirouterAndStargateRouter[0], _vault, _beefyFeeRecipientAndKeeper[0]
    ) StrategyTridentRouter(
        _unirouterAndStargateRouter[0], _outputToNativeRoute, _outputToLp0Route, _outputToNativePoolRoute, _outputToLp0PoolRoute
    ) public {
        want = _want;
        poolId = _poolIdAndRouterPoolId[0];
        routerPoolId = _poolIdAndRouterPoolId[1];
        chef = _chef;
        stargateRouter = _unirouterAndStargateRouter[1];
        bento = address(0x0319000133d3AdA02600f0875d2cf03D442C3367); // bento V1 matic
        
        // routes defined in inhereited StrategyTridentRouter
        output = outputToNativeRoute[0][0];
        native = outputToNativeRoute[outputToNativeRoute.length - 1][1];
        lpToken0 = outputToLp0Route[outputToLp0Route.length - 1][1];
        
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMasterChef(chef).deposit(poolId, wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChef(chef).withdraw(poolId, _amount.sub(wantBal));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal.mul(withdrawalFee).div(WITHDRAWAL_MAX);
            wantBal = wantBal.sub(withdrawalFeeAmount);
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

    function harvest() external gasThrottle virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external gasThrottle virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IMasterChef(chef).deposit(poolId, 0);
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        uint256 toNative = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        tridentSwap(output, toNative, outputToNativePath);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));

        if (lpToken0 != output) {
            tridentSwap(output, outputBal, outputToLp0Path);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        IStargateRouter(stargateRouter).addLiquidity(routerPoolId, lp0Bal, address(this));
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount,) = IMasterChef(chef).userInfo(poolId, address(this));
        return _amount;
    }

    function setPendingRewardsFunctionName(string calldata _pendingRewardsFunctionName) external onlyManager {
        pendingRewardsFunctionName = _pendingRewardsFunctionName;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        string memory signature = StringUtils.concat(pendingRewardsFunctionName, "(uint256,address)");
        bytes memory result = Address.functionStaticCall(
            chef, 
            abi.encodeWithSignature(
                signature,
                poolId,
                address(this)
            )
        );  
        return abi.decode(result, (uint256));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        uint256 amountOut;
        if (outputBal > 0) {
            uint256 amountIn = outputBal;
            address tokenIn = output;
            for (uint256 i; i < outputToNativePoolRoute.length - 1; ) {
                amountOut = IPool(outputToNativePoolRoute[i]).getAmountOut(abi.encode(tokenIn,amountIn));
                amountIn = amountOut;
                ++i;
            }
        }
        nativeOut = amountOut;
        return nativeOut.mul(45).div(1000).mul(callFee).div(MAX_FEE);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IMasterChef(chef).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IMasterChef(chef).emergencyWithdraw(poolId);
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
        IERC20(want).safeApprove(chef, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken0).safeApprove(stargateRouter, 0);
        IERC20(lpToken0).safeApprove(stargateRouter, uint256(-1));

        IBentoBoxMinimal(bento).setMasterContractApproval(address(this),unirouter,true,0,0,0);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(stargateRouter, 0);
    }

    function outputToNativePool() external view returns (address[] memory) {
        return outputToNativePoolRoute; 
    }

    function outputToLp0Pool() external view returns (address[] memory) {
        return outputToLp0PoolRoute; 
    }

    function outputToNative() external view returns (address[][] memory) {
        return outputToNativeRoute; 
    }

    function outputToLp0() external view returns (address[][] memory) {
        return outputToLp0Route; 
    }
}

/// @notice Minimal BentoBox vault interface.
/// @dev `token` is aliased as `address` from `IERC20` for simplicity.
interface IBentoBoxMinimal {
    /// @notice Balance per ERC-20 token per account in shares.
    function balanceOf(address, address) external view returns (uint256);

    /// @dev Helper function to represent an `amount` of `token` in shares.
    /// @param token The ERC-20 token.
    /// @param amount The `token` amount.
    /// @param roundUp If the result `share` should be rounded up.
    /// @return share The token amount represented in shares.
    function toShare(
        address token,
        uint256 amount,
        bool roundUp
    ) external view returns (uint256 share);

    /// @dev Helper function to represent shares back into the `token` amount.
    /// @param token The ERC-20 token.
    /// @param share The amount of shares.
    /// @param roundUp If the result should be rounded up.
    /// @return amount The share amount back into native representation.
    function toAmount(
        address token,
        uint256 share,
        bool roundUp
    ) external view returns (uint256 amount);

    /// @notice Registers this contract so that users can approve it for BentoBox.
    function registerProtocol() external;

    /// @notice Deposit an amount of `token` represented in either `amount` or `share`.
    /// @param token The ERC-20 token to deposit.
    /// @param from which account to pull the tokens.
    /// @param to which account to push the tokens.
    /// @param amount Token amount in native representation to deposit.
    /// @param share Token amount represented in shares to deposit. Takes precedence over `amount`.
    /// @return amountOut The amount deposited.
    /// @return shareOut The deposited amount represented in shares.
    function deposit(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable returns (uint256 amountOut, uint256 shareOut);

    /// @notice Withdraws an amount of `token` from a user account.
    /// @param token_ The ERC-20 token to withdraw.
    /// @param from which user to pull the tokens.
    /// @param to which user to push the tokens.
    /// @param amount of tokens. Either one of `amount` or `share` needs to be supplied.
    /// @param share Like above, but `share` takes precedence over `amount`.
    function withdraw(
        address token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);

    /// @notice Transfer shares from a user account to another one.
    /// @param token The ERC-20 token to transfer.
    /// @param from which user to pull the tokens.
    /// @param to which user to push the tokens.
    /// @param share The amount of `token` in shares.
    function transfer(
        address token,
        address from,
        address to,
        uint256 share
    ) external;

    /// @dev Approves users' BentoBox assets to a "master" contract.
    function setMasterContractApproval(
        address user,
        address masterContract,
        bool approved,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}