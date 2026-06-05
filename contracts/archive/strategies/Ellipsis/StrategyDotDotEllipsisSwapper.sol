// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/curve/ICurveSwap.sol";
import "./IDotDot.sol";
import "./IEpsSwap.sol";
import "../Common/StratFeeManager.sol";
import "../../utils/GasFeeThrottler.sol";

contract StrategyDotDotEllipsisSwapper is StratFeeManager, GasFeeThrottler {
    using SafeERC20 for IERC20;

    // Tokens used
    address public epx = 0xAf41054C1487b0e5E2B9250C0332eCBCe6CE9d71;
    address public depx = 0x772F317ec695ce20290b56466b3f48501ba81352;
    address public ddd = 0x84c97300a190676a19D1E13115629A11f8482Bd1;
    address public native = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    // Third party contracts
    IDotDotLpDepositor public lpDepositor = IDotDotLpDepositor(0x8189F0afdBf8fE6a9e13c69bA35528ac6abeB1af);
    IDotDotBondedFeeDistributor public feeDistributor = IDotDotBondedFeeDistributor(0xd4F7b4BC46e6e499D35335D270fd094979D815A0);
    address public depxEpxSwap = 0x45859D71D4caFb93694eD43a5ecE05776Fc2465d;
    address public epxBnbSwap = 0xE014A89c9788dAfdE603a13F2f01390610382471;

    address public want; // ellipsis lpToken
    address public receiptToken; // receipt token minted/burned by LpDepositor lpDepositor.depositTokens(want)
    address public depositToken;

    // Routes
    address[] public dddToNativeRoute = [ddd, native];

    address[] public rewards;

    // claim EPX as bonded dEPX to receive 3x DDD
    bool public claimAsBondedEpx = true;

    // if depositToken should be sent as unwrapped native
    bool public depositNative;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        address _depositToken,
        CommonAddresses memory _commonAddresses
    ) StratFeeManager(_commonAddresses) {
        want = _want;
        receiptToken = lpDepositor.depositTokens(want);
        depositToken = _depositToken;

        harvestOnDeposit = true;
        withdrawalFee = 0;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            lpDepositor.deposit(address(this), want, wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            lpDepositor.withdraw(address(this), want, _amount - wantBal);
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
        claimRewards();
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

    function claimRewards() internal {
        // epx + ddd
        address[] memory wants = new address[](1);
        wants[0] = want;
        IDotDotLpDepositor.Amounts[] memory amounts = lpDepositor.claimable(address(this), wants);
        uint claimableEpx = amounts[0].epx;
        uint bondedAmount = claimAsBondedEpx && claimableEpx > 0 ? type(uint).max : 0;
        lpDepositor.claim(address(this), wants, bondedAmount);

        // extras
        if (rewards.length > 0) {
            lpDepositor.claimExtraRewards(address(this), want);
        }

        // bonded fees
        if (claimAsBondedEpx) {
            address[] memory tokens = new address[](2);
            tokens[0] = epx;
            tokens[1] = ddd;
            // epx + ddd
            feeDistributor.claim(address(this), tokens);
            // dEpx
            (uint claimable, uint total) = feeDistributor.streamingBalances(address(this));
            if (claimable > 0) {
                feeDistributor.withdrawUnbondedTokens(address(this));
            }
            // start streaming dEpx if unbondable > currently streaming as stream will reset
            uint unbondableBal = feeDistributor.unbondableBalance(address(this));
            if (unbondableBal > total - claimable) {
                feeDistributor.initiateUnbondingStream(unbondableBal);
            }
        }
    }

    function swapRewardsToNative() internal {
        _swap(ddd, native);
        _swap(depx, epx);
        _swap(epx, native);
        // extras
        for (uint i; i < rewards.length; i++) {
            _swap(rewards[i], native);
        }
        // wrap native, could be sent from ellipsis bnb swap pools
        uint256 nativeBal = address(this).balance;
        if (nativeBal > 0) {
            IWrappedNative(native).deposit{value: nativeBal}();
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeFeeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeFeeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeFeeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeFeeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        if (depositToken != native) {
            _swap(native, depositToken);
        }
        _swap(depositToken, want);
    }

    function _swap(address tokenFrom, address tokenTo) internal {
        uint amount = IERC20(tokenFrom).balanceOf(address(this));
        if (amount > 0) {
            IERC20(tokenFrom).approve(unirouter, 0);
            IERC20(tokenFrom).approve(unirouter, amount);
            IBeefySwapper(unirouter).swap(tokenFrom, tokenTo, amount);
        }
    }

    function addRewardToken(address token) external onlyManager {
        require(token != want, "!want");
        require(token != native, "!native");
        require(token != epx, "!epx");
        require(token != ddd, "!ddd");
        require(token != receiptToken, "!receipt");
        rewards.push(token);
    }

    function resetRewardTokens() external onlyManager {
        delete rewards;
    }

    // claim additional trading fees for bonding EPX, usually too small amounts to include in rewards by default
    function claimFeeDistributor(address[] calldata _tokens) external onlyManager {
        feeDistributor.claim(address(this), _tokens);
    }

    // claim EPX as bonded dEPX to receive 3x DDD
    function setClaimAsBondedEpx(bool _bond) external onlyManager {
        claimAsBondedEpx = _bond;
    }

    function bondedEpx() external view returns (uint bonded, uint unbondable, uint claimable, uint totalStreaming) {
        bonded = feeDistributor.bondedBalance(address(this));
        unbondable = feeDistributor.unbondableBalance(address(this));
        (claimable, totalStreaming) = feeDistributor.streamingBalances(address(this));
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
    function balanceOfPool() public view returns (uint256) {
        return lpDepositor.userBalances(address(this), want);
    }

    function rewardsLength() external view returns (uint) {
        return rewards.length;
    }

    function setDepositNative(bool _depositNative) external onlyOwner {
        depositNative = _depositNative;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256, uint256) {
        address[] memory tokens = new address[](1);
        tokens[0] = want;
        IDotDotLpDepositor.Amounts[] memory amounts = lpDepositor.claimable(address(this), tokens);
        return (amounts[0].epx, amounts[0].ddd);
    }

    function rewardsBondedAvailable() public view returns (uint256, uint256) {
        address[] memory tokens = new address[](2);
        tokens[0] = epx;
        tokens[1] = ddd;
        uint256[] memory amounts = feeDistributor.claimable(address(this), tokens);
        return (amounts[0], amounts[1]);
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        (uint epxBal, uint dddBal) = rewardsAvailable();

        uint256 nativeOut;
        if (claimAsBondedEpx) {
            (uint epxFeeBal, uint dddFeeBal) = rewardsBondedAvailable();
            epxBal = epxFeeBal;
            // 3x DDD
            dddBal = dddBal * 3 + dddFeeBal;
            uint256[] memory amountOut = IUniswapRouterETH(unirouter).getAmountsOut(dddBal, dddToNativeRoute);
            nativeOut = nativeOut + amountOut[amountOut.length - 1];
            // dEPX to EPX
            (uint256 claimable,) = feeDistributor.streamingBalances(address(this));
            if (claimable > 0) {
                epxBal = epxBal + IEpsSwap(depxEpxSwap).get_dy(0, 1, claimable);
            }
            if (epxBal > 0) {
                nativeOut = nativeOut + IEpsSwap(epxBnbSwap).get_dy(0, 1, epxBal);
            }
        } else {
            // ddd
            uint256[] memory amountOut = IUniswapRouterETH(unirouter).getAmountsOut(dddBal, dddToNativeRoute);
            nativeOut = nativeOut + amountOut[amountOut.length - 1];
            // epx
            nativeOut = nativeOut + IEpsSwap(epxBnbSwap).get_dy(0, 1, epxBal);
        }

        IFeeConfig.FeeCategory memory fees = getFees();
        return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        lpDepositor.withdraw(address(this), want, balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        lpDepositor.withdraw(address(this), want, balanceOfPool());
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
        IERC20(want).approve(address(lpDepositor), type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).approve(address(lpDepositor), 0);
    }

    receive () external payable {}
}
