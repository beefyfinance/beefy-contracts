// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/common/IUniswapRouter.sol";
import "../../interfaces/pancake/IMasterChef.sol";
import "../../utils/GasThrottler.sol";

/**
 * @dev Strategy to farm MASH through a Pancake based MasterChef contract.
 */
contract StrategyMash is Ownable, Pausable, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /**
     * @dev Tokens Used:
     * {wbnb} - Required for liquidity routing when doing swaps.
     * {want} - Token that the strategy maximizes. The same token that users deposit in the vault. MASH
     * {bifi} - BeefyFinance token, used to send funds to the treasury.
     */
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public want = address(0x787732f27D18495494cea3792ed7946BbCFF8db2);
    address constant public bifi = address(0xCa3F508B8e4Dd382eE878A314789373D80A5190A);

    /**
     * @dev Third Party Contracts:
     * {unirouter} - PancakeSwap unirouter
     * {masterchef} - MasterChef contract
     * {poolId} - MasterChef pool id for single {want} staking
     */
    address constant public unirouter  = address(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    address constant public masterchef = address(0x8932a6265b01D1D4e1650fEB8Ac38f9D79D3957b);
    uint8 constant public poolId = 4;

    /**
     * @dev Beefy Contracts:
     * {rewards} - Reward pool where the strategy fee earnings will go.
     * {treasury} - Address of the BeefyFinance treasury
     * {vault} - Address of the vault that controls the strategy's funds.
     * {strategist} - Address of the strategy author/deployer where strategist fee will go.
     */
    address constant public rewards  = address(0x453D4Ba9a2D594314DF88564248497F7D74d6b2C);
    address constant public treasury = address(0x4A32De8c248533C28904b24B4cFCFE18E9F2ad01);
    address public vault;
    address public strategist;

    /**
     * @dev Distribution of fees earned. This allocations relative to the % implemented on doSplit().
     * Current implementation separates 4.5% for fees.
     *
     * {TREASURY_FEE} - 0.5% goes to the treasury.
     * {STRATEGIST_FEE} - 0.5% goes to the strategist.
     * {MAX_FEE} - Aux const used to safely calc the correct amounts.
     * {MAX_CALL_FEE} - Max value that the {callFee} can be configured to.
     *
     * {WITHDRAWAL_FEE} - Fee taxed when a user withdraws funds. 10 === 0.1% fee.
     * {WITHDRAWAL_MAX} - Aux const used to safely calc the correct amounts.
     *
     * {callFee} - 0.25% goes to whoever executes the harvest. Can be lowered.
     * {rewardsFee} - 3% that goes to BIFI holders. Can be increased by decreasing {callFee}.
     */
    uint constant public TREASURY_FEE   = 112;
    uint constant public STRATEGIST_FEE = 112;
    uint constant public MAX_FEE        = 1000;
    uint constant public MAX_CALL_FEE = 111;

    uint constant public WITHDRAWAL_FEE = 10;
    uint constant public WITHDRAWAL_MAX = 10000;

    uint public callFee = 55;
    uint public rewardsFee = MAX_FEE - TREASURY_FEE - STRATEGIST_FEE - callFee;

    /**
     * @dev Routes we take to swap tokens using PancakeSwap
     * {wantToWbnbRoute} - Route we take to go from {want} into {wbnb}.
     * {wbnbToBifiRoute} - Route we take to go from {wbnb} into {bifi}.
     */
    address[] public wantToWbnbRoute = [want, wbnb];
    address[] public wbnbToBifiRoute = [wbnb, bifi];

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);

    /**
     * @dev Initializes the strategy with the token that it will look to maximize.
     * @param _vault Address to initialize {vault}
     * @param _strategist Address to initialize {strategist}
     */
    constructor(address _vault, address _strategist) public {
        vault = _vault;
        strategist = _strategist;

        IERC20(want).safeApprove(masterchef, uint(-1));
        IERC20(want).safeApprove(unirouter, uint(-1));
        IERC20(wbnb).safeApprove(unirouter, uint(-1));
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * It deposits {want} in the MasterChef to earn rewards in {want}.
     */
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMasterChef(masterchef).deposit(poolId, wantBal);
        }
    }

    /**
     * @dev It withdraws {want} from the MasterChef and sends it to the vault.
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
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * 1. It claims rewards from the MasterChef
     * 3. It charges the system fee and sends it to BIFI stakers.
     * 4. It re-invests the remaining profits.
     */
    function harvest() public whenNotPaused gasThrottle {
        require(tx.origin == msg.sender || msg.sender == vault, "!contract");
        IMasterChef(masterchef).deposit(poolId, 0);
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        if (wantBal > 0) {
            chargeFees();
            deposit();
            emit StratHarvest(msg.sender);
        }
    }

    /**
     * @dev Takes out 4.5% as system fees from the rewards.
     * 0.5% -> Call Fee
     * 0.5% -> Treasury fee
     * 0.5% -> Strategist fee
     * 3.0% -> BIFI Holders
     */
    function chargeFees() internal {
        uint256 toWbnb = IERC20(want).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouter(unirouter).swapExactTokensForTokens(toWbnb, 0, wantToWbnbRoute, address(this), now.add(600));

        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));

        uint256 callFeeAmount = wbnbBal.mul(callFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(msg.sender, callFeeAmount);

        uint256 treasuryHalf = wbnbBal.mul(TREASURY_FEE).div(MAX_FEE).div(2);
        IERC20(wbnb).safeTransfer(treasury, treasuryHalf);
        IUniswapRouter(unirouter).swapExactTokensForTokens(treasuryHalf, 0, wbnbToBifiRoute, treasury, now.add(600));

        uint256 rewardsFeeAmount = wbnbBal.mul(rewardsFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(rewards, rewardsFeeAmount);

        uint256 strategistFee = wbnbBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(strategist, strategistFee);
    }

    /**
     * @dev Function to synchronize balance of {want}.
     * It harvests pending rewards from the pool.
     */
    function updateBalance() public {
        harvest();
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

        uint256 wanBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wanBal);
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from the MasterChef, leaving rewards behind
     */
    function panic() public onlyOwner {
        pause();
        IMasterChef(masterchef).emergencyWithdraw(poolId);
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public onlyOwner {
        _pause();

        IERC20(want).safeApprove(masterchef, 0);
        IERC20(want).safeApprove(unirouter, 0);
        IERC20(wbnb).safeApprove(unirouter, 0);
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external onlyOwner {
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
     * @dev Updates the harvest {callFee}. Capped by {MAX_CALL_FEE}.
     * @param _fee new fee to give harvesters.
     */
    function setCallFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_CALL_FEE, "!cap");

        callFee = _fee;
        rewardsFee = MAX_FEE - TREASURY_FEE - STRATEGIST_FEE - callFee;
    }
}