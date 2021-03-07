// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/common/IUniswapRouter.sol";
import "../../interfaces/common/IRewardPool.sol";

/**
 * @dev Strategy to farm BHC through a Synthetix based rewards pool contract.
 */
contract StrategyBillion is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /**
     * @dev Tokens Used:
     * {wbnb} - Required for liquidity routing and to pay out fees.
     * {bhc} - Token that the strategy maximizes. The same token that users deposit in the vault.
     * {bifi} - BeefyFinance token, used to send funds to the treasury.
     */
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public bhc = address(0x6fd7c98458a943f469E1Cf4eA85B173f5Cd342F4);
    address constant public bifi = address(0xCa3F508B8e4Dd382eE878A314789373D80A5190A);

    /**
     * @dev Third Party Contracts:
     * {unirouter} - StreetSwap unirouter
     * {rewardPool} - Reward pool contract. Stake {bhc}, get {bhc}.
     */
    address constant public unirouter = address(0x3bc677674df90A9e5D741f28f6CA303357D0E4Ec);
    address constant public rewardPool = address(0xF867ea84d04C79Bbd812E76F3eCeDF3d053fFf91);

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
     * @dev Distribution of fees earned. This allocations relative to the % implemented on chargeFees().
     * Current implementation separates 4.5% for fees.
     *
     * {REWARDS_FEE} - 3% goes to BIFI holders through the {rewards} pool.
     * {CALL_FEE} - 0.5% goes to whoever executes the harvest function as gas subsidy.
     * {TREASURY_FEE} - 0.5% goes to the treasury.
     * {STRATEGIST_FEE} - 0.5% goes to the strategist.
     * {MAX_FEE} - Aux const used to safely calc the correct amounts.
     *
     * {WITHDRAWAL_FEE} - Fee taxed when a user withdraws funds. 10 === 0.1% fee.
     * {WITHDRAWAL_MAX} - Aux const used to safely calc the correct amounts.
     */
    uint constant public REWARDS_FEE  = 667;
    uint constant public CALL_FEE     = 111;
    uint constant public TREASURY_FEE = 111;
    uint constant public STRATEGIST_FEE = 111;
    uint constant public MAX_FEE      = 1000;

    uint constant public WITHDRAWAL_FEE = 10;
    uint constant public WITHDRAWAL_MAX = 10000;

    /**
     * @dev Routes we take to swap tokens using Thugswap.
     * {bhcToWbnbRoute} - Route we take to go from {bhc} into {wbnb}.
     * {wbnbToBifiRoute} - Route we take to go from {wbnb} into {bifi}.
     */
    address[] public bhcToWbnbRoute = [bhc, wbnb];
    address[] public wbnbToBifiRoute = [wbnb, bifi];

    /**
     * @dev Initializes the strategy with the token that it will look to maximize.
     * @param _vault Address to initialize {vault}
     * @param _strategist Address to initialize {strategist}
     */
    constructor(address _vault, address _strategist) public {
        vault = _vault;
        strategist = _strategist;

        IERC20(bhc).safeApprove(rewardPool, uint256(-1));
        IERC20(bhc).safeApprove(unirouter, uint256(-1));
        IERC20(wbnb).safeApprove(unirouter, uint256(-1));
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * It deposits {bhc} in the reward pool to earn {bhc}.
     */
    function deposit() public whenNotPaused {
        uint256 bhcBal = IERC20(bhc).balanceOf(address(this));

        if (bhcBal > 0) {
            IRewardPool(rewardPool).stake(bhcBal);
        }
    }

    /**
     * @dev It withdraws {bhc} from the reward pool and sends it to the vault.
     * @param _amount How much {bhc} to withdraw.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 bhcBal = IERC20(bhc).balanceOf(address(this));

        if (bhcBal < _amount) {
            IRewardPool(rewardPool).withdraw(_amount.sub(bhcBal));
            bhcBal = IERC20(bhc).balanceOf(address(this));
        }

        if (bhcBal > _amount) {
            bhcBal = _amount;    
        }
        
        if (tx.origin == owner()) {
            IERC20(bhc).safeTransfer(vault, bhcBal);
        } else {
            uint256 withdrawalFee = bhcBal.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
            IERC20(bhc).safeTransfer(vault, bhcBal.sub(withdrawalFee));
        }
    }

    /**
     * @dev In charge of collecting and re-investing rewards.
     * 1. It claims rewards from the IRewardPool.
     * 3. It charges and distributes system fees.
     * 4. It re-invests the remaining profits.
     */
    function harvest() external whenNotPaused {
        require(!Address.isContract(msg.sender), "!contract");
        IRewardPool(rewardPool).getReward();
        chargeFees();
        deposit();
    }

    /**
     * @dev Takes out 4.5% as system fees from the rewards. 
     * 3.0% -> BIFI Holders
     * 0.5% -> Treasury fee
     * 0.5% -> Strategist Fee
     * 0.5% -> Call Fee
     */
    function chargeFees() internal {
        uint256 toWbnb = IERC20(bhc).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouter(unirouter).swapExactTokensForTokens(toWbnb, 0, bhcToWbnbRoute, address(this), now.add(600));
    
        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));
        
        uint256 callFee = wbnbBal.mul(CALL_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(msg.sender, callFee);
        
        uint256 treasuryHalf = wbnbBal.mul(TREASURY_FEE).div(MAX_FEE).div(2);
        IERC20(wbnb).safeTransfer(treasury, treasuryHalf);
        IUniswapRouter(unirouter).swapExactTokensForTokens(treasuryHalf, 0, wbnbToBifiRoute, treasury, now.add(600));
        
        uint256 rewardsFee = wbnbBal.mul(REWARDS_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(rewards, rewardsFee);

        uint256 strategistFee = wbnbBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(strategist, strategistFee);
    }

    /**
     * @dev Function to calculate the total underlying {bhc} held by the strat.
     * It takes into account both the funds at hand, and the funds allocated in the reward pool.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfBhc().add(balanceOfPool());
    }

    /**
     * @dev It calculates how much {bhc} the contract holds.
     */
    function balanceOfBhc() public view returns (uint256) {
        return IERC20(bhc).balanceOf(address(this));
    }

    /**
     * @dev It calculates how much {bhc} the strategy has allocated in the reward pool.
     */
    function balanceOfPool() public view returns (uint256) {
        return IRewardPool(rewardPool).balanceOf(address(this));
    }

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the 
     * vault, ready to be migrated to the new strat.
     */
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IRewardPool(rewardPool).withdraw(balanceOfPool());

        uint256 bhcBal = IERC20(bhc).balanceOf(address(this));
        IERC20(bhc).transfer(vault, bhcBal);
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from the reward pool, leaving rewards behind
     */
    function panic() external onlyOwner {
        pause();
        IRewardPool(rewardPool).withdraw(balanceOfPool());
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public onlyOwner {
        _pause();

        IERC20(bhc).safeApprove(rewardPool, 0);
        IERC20(bhc).safeApprove(unirouter, 0);
        IERC20(wbnb).safeApprove(unirouter, 0);
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external onlyOwner {
        _unpause();

        IERC20(bhc).safeApprove(rewardPool, uint256(-1));
        IERC20(bhc).safeApprove(unirouter, uint256(-1));
        IERC20(wbnb).safeApprove(unirouter, uint256(-1));

        deposit();
    }

    /**
     * @dev Updates address where strategist fee earnings will go.
     * @param _strategist new strategist address.
     */
    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "!strategist");
        strategist = _strategist;
    }
}