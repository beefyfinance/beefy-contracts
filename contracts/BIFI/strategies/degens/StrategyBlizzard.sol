// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/pancake/IMasterChef.sol";
import "../../utils/GasThrottler.sol";

/**
 * @dev Strategy to farm xBLZD on Blizzard.Money.
 */
contract StrategyBlizzard is Ownable, Pausable, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /**
     * @dev Tokens Used:
     * {wbnb} - Required for liquidity routing when doing swaps.
     * {want} - Token that the strategy maximizes. In this case, xBLZD.
     * {bifi} - BeefyFinance token, used to send funds to the treasury.
     */
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public want = address(0x9a946c3Cb16c08334b69aE249690C236Ebd5583E);
    address constant public bifi = address(0xCa3F508B8e4Dd382eE878A314789373D80A5190A);

    /**
     * @dev Third Party Contracts:
     * {unirouter} - PancakeSwap unirouter
     * {masterchef} - MasterChef contract
     * {poolId} - MasterChef pool id
     */
    address constant public unirouter  = address(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    address constant public masterchef = address(0x367CdDA266ADa588d380C7B970244434e4Dde790);
    uint8 public poolId;

    /**
     * @dev Beefy Contracts:
     * {rewards} - Reward pool where the strategy fee earnings will go.
     * {treasury} - Address of the BeefyFinance treasury
     * {vault} - Address of the vault that controls the strategy's funds.
     * {strategist} - Address of the strategy author/deployer where strategist fee will go.
     * {keeper} - Address used as an extra strat manager.
     */
    address constant public rewards  = address(0x453D4Ba9a2D594314DF88564248497F7D74d6b2C);
    address constant public treasury = address(0x4A32De8c248533C28904b24B4cFCFE18E9F2ad01);
    address public vault;
    address public strategist;
    address public keeper;

    /**
     * @dev Distribution of fees earned. This allocations relative to the % implemented on doSplit().
     * Current implementation separates 4.5% for fees.
     *
     * {TREASURY_FEE} - 0.5% goes to the treasury.
     * {STRATEGIST_FEE} - 0.5% goes to the strategist.
     * {MAX_CALL_FEE} - Max value that the {callFee} can be configured to.
     * {MAX_FEE} - Aux const used to safely calc the correct amounts.
     * {callFee} - 0.25% goes to whoever executes the harvest. Can be adjusted.
     * {rewardsFee} - 3.25% goes to BIFI holders through the {rewards} pool. Adjusted by callFee changes.
     *
     * {WITHDRAWAL_FEE} - Fee taxed when a user withdraws funds. 10 === 0.1% fee.
     * {WITHDRAWAL_MAX} - Aux const used to safely calc the correct amounts.
     */
    uint constant public TREASURY_FEE   = 112;
    uint constant public STRATEGIST_FEE = 112;
    uint constant public MAX_CALL_FEE   = 111;
    uint constant public MAX_FEE        = 1000;
    uint public callFee                 = 56;
    uint public rewardsFee              = MAX_FEE - TREASURY_FEE - STRATEGIST_FEE - callFee;

    uint constant public WITHDRAWAL_FEE = 10;
    uint constant public WITHDRAWAL_MAX = 10000;

    /**
     * @dev Routes we take to swap tokens using PancakeSwap.
     * {wantToWbnbRoute} - Route we take to get from {want} into {wbnb}.
     * {wbnbToBifiRoute} - Route we take to get from {wbnb} into {bifi}.
     */
    address[] public wantToWbnbRoute = [want, wbnb];
    address[] public wbnbToBifiRoute = [wbnb, bifi];

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest();

    /**
     * @dev Initializes the strategy with the token to maximize.
     */
    constructor(uint8 _poolId, address _vault, address _strategist) public {
        poolId = _poolId;
        vault = _vault;
        strategist = _strategist;

        IERC20(want).safeApprove(masterchef, uint(-1));
        IERC20(want).safeApprove(unirouter, uint(-1));
        IERC20(wbnb).safeApprove(unirouter, uint(-1));
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     */
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMasterChef(masterchef).deposit(poolId, wantBal);
        }
    }

    /**
     * @dev Withdraws {want} from the MasterChef and sends it to the Vault.
     * Fees are not assessed if the Vault is paused.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChef(masterchef).withdraw(poolId, _amount.sub(wantBal));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin == owner() || paused()) {
            IERC20(want).safeTransfer(vault, wantBal);
        } else {
            uint256 withdrawalFee = wantBal.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
            IERC20(want).safeTransfer(vault, wantBal.sub(withdrawalFee));
        }
    }

    /**
     * @dev Public harvest. Doesn't work when the strat is paused.
     */
    function harvest() external whenNotPaused {
        _harvest();
    }

    /**
     * @dev Harvest to keep the strat working while paused. Helpful in some cases.
     */
    function sudoHarvest() external {
        require(msg.sender == owner() || msg.sender == keeper, "!authorized");

        _harvest();
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * 1. It claims rewards from the MasterChef.
     * 2. It charges the system fee and sends it to BIFI stakers.
     * 3. It re-invests the remaining profits.
     */
    function _harvest() internal gasThrottle {
        IMasterChef(masterchef).deposit(poolId, 0);
        chargeFees();
        deposit();

        emit StratHarvest();
    }

    /**
     * @dev Takes out 4.5% as system fees from the rewards.
     * 0.25% -> Call Fee
     * 0.5% -> Treasury fee
     * 0.5% -> Strategist fee
     * 3.25% -> BIFI Holders
     */
    function chargeFees() internal {
        uint256 toWbnb = IERC20(want).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toWbnb, 0, wantToWbnbRoute, address(this), now.add(600));

        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));

        uint256 callFeeAmount = wbnbBal.mul(callFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(msg.sender, callFeeAmount);

        uint256 treasuryHalf = wbnbBal.mul(TREASURY_FEE).div(MAX_FEE).div(2);
        IERC20(wbnb).safeTransfer(treasury, treasuryHalf);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(treasuryHalf, 0, wbnbToBifiRoute, treasury, now.add(600));

        uint256 rewardsFeeAmount = wbnbBal.mul(rewardsFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(rewards, rewardsFeeAmount);

        uint256 strategistFee = wbnbBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(strategist, strategistFee);
    }

    /**
     * @dev Function to calculate the total underlying {want} held by the strat.
     * It takes into account both the funds in hand, as the funds allocated in the MasterChef.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    /**
     * @dev It calculates how much {want} the contract holds.
     */
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /**
     * @dev It calculates how much {want} the strategy has allocated in the MasterChef
     */
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount, ) = IMasterChef(masterchef).userInfo(poolId, address(this));
        return _amount;
    }

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the
     * vault, ready to be migrated to the new strat.
     */
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IMasterChef(masterchef).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from the MasterChef, leaving rewards behind
     */
    function panic() public {
        require(msg.sender == owner() || msg.sender == keeper, "!authorized");

        pause();
        IMasterChef(masterchef).emergencyWithdraw(poolId);
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public {
        require(msg.sender == owner() || msg.sender == keeper, "!authorized");

        _pause();

        IERC20(want).safeApprove(masterchef, 0);
        IERC20(want).safeApprove(unirouter, 0);
        IERC20(wbnb).safeApprove(unirouter, 0);
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external {
        require(msg.sender == owner() || msg.sender == keeper, "!authorized");

        _unpause();

        IERC20(want).safeApprove(masterchef, uint(-1));
        IERC20(want).safeApprove(unirouter, uint(-1));
        IERC20(wbnb).safeApprove(unirouter, uint(-1));
    }

    /**
     * @dev Updates address where strategist fee earnings will go.
     * @param _strategist new strategist address.
     */
    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "!strategist");
        strategist = _strategist;
    }

    /**
     * @dev Updates address of the strat keeper.
     * @param _keeper new keeper address.
     */
    function setKeeper(address _keeper) external {
        require(msg.sender == owner() || msg.sender == keeper, "!authorized");

        keeper = _keeper;
    }

    /**
     * @dev Updates the harvest {callFee}. Capped by {MAX_CALL_FEE}.
     * @param _fee new fee to give harvesters.
     */
    function setCallFee(uint256 _fee) external {
        require(msg.sender == owner() || msg.sender == keeper, "!authorized");
        require(_fee < MAX_CALL_FEE, "!cap");

        callFee = _fee;
        rewardsFee = MAX_FEE - TREASURY_FEE - STRATEGIST_FEE - callFee;
    }

    /**
     * @dev Rescues random funds stuck that the strat can't handle.
     * @param _token address of the token to rescue.
     */
    function inCaseTokensGetStuck(address _token) external {
        require(msg.sender == owner() || msg.sender == keeper, "!authorized");

        require(_token != want, "!want");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}
