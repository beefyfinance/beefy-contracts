// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/common/IWBNB.sol";
import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IRewardPool.sol";

/**
 * @dev BIFI MAXIMALIST STRATEGY. DEPOSIT BIFI. USE THE BNB REWARDS TO GET MORE BIFI!
 */
contract StrategyBifiMaxi is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /**
     * @dev Tokens Used:
     * {wbnb} - The token that rewards are paid in.
     * {bifi} - BeefyFinance token. The token this strategy looks to maximize.
     */
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public bifi = address(0xCa3F508B8e4Dd382eE878A314789373D80A5190A);

    /**
     * @dev Third Party Contracts:
     * {unirouter} - Streetswap router to use as AMM.
     */
    address constant public unirouter = address(0x3bc677674df90A9e5D741f28f6CA303357D0E4Ec);

    /**
     * @dev Beefy Contracts:
     * {rewards} - Reward pool where the {bifi} is staked.
     * {vault} - Address of the vault that controls the strategy's funds.
     */
    address constant public rewards  = address(0x453D4Ba9a2D594314DF88564248497F7D74d6b2C);
    address public vault;

    /**
     * @dev Distribution of fees earned. This allocations relative to the % implemented on chargeFees().
     * Current implementation separates 1% total for fees.
     *
     * {REWARDS_FEE} - 0.5% goes to BIFI holders through the {rewards} pool.
     * {CALL_FEE} - 0.5% goes to pay for harvest execution.
     * {MAX_FEE} - Aux const used to safely calc the correct amounts.
     * 
     * {WITHDRAWAL_FEE} - Fee taxed when a user withdraws funds. 5 === 0.05% fee.
     * {WITHDRAWAL_MAX} - Aux const used to safely calc the correct amounts.
     */
    uint constant public REWARDS_FEE  = 5;
    uint constant public CALL_FEE     = 5;
    uint constant public MAX_FEE      = 1000;

    uint constant public WITHDRAWAL_FEE = 5;
    uint constant public WITHDRAWAL_MAX = 10000;

    /**
     * @dev Routes we take to swap tokens using Thugswap.
     * {wbnbToBifiRoute} - Route we take to get from {wbnb} into {bifi}.
     */
    address[] public wbnbToBifiRoute = [wbnb, bifi];
  
    /**
     * @dev Initializes the strategy with the token to maximize.
     */
    constructor(address _vault) public {
        vault = _vault;

        IERC20(wbnb).safeApprove(unirouter, uint(-1));
        IERC20(bifi).safeApprove(rewards, uint(-1));
    }
    
    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * It stakes the received {bifi} into the {rewards} pool.
     */
    function deposit() public whenNotPaused {
        uint256 bifiBal = IERC20(bifi).balanceOf(address(this));

        if (bifiBal > 0) {
            IRewardPool(rewards).stake(bifiBal);
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     * It withdraws {bifi} from the {rewards} pool.
     * The available {bifi} minus a withdrawal fee is returned to the vault.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 bifiBal = IERC20(bifi).balanceOf(address(this));

        if (bifiBal < _amount) {   
            IRewardPool(rewards).withdraw(_amount.sub(bifiBal));
            bifiBal = IERC20(bifi).balanceOf(address(this));
        }

        if (bifiBal > _amount) {
            bifiBal = _amount;    
        }
        
        uint256 withdrawalFee = bifiBal.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
        IERC20(bifi).safeTransfer(vault, bifiBal.sub(withdrawalFee));
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * 1. It claims rewards from the RewardPool.
     * 2. It charges a small system fee.
     * 3. It swaps the {wbnb} token for more {bifi}
     * 4. It deposits the {bifi} back into the pool.
     */
    function harvest() external whenNotPaused onlyOwner {
        require(!Address.isContract(msg.sender), "!contract");
        IRewardPool(rewards).getReward();
        chargeFees();
        swapRewards();
        deposit();
    }

    /**
     * @dev Takes out 1% as system fees from the rewards. 
     * 0.5% -> Call Fee
     * 0.5% -> Rewards fee
     */
    function chargeFees() internal {
        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));

        uint256 callFee = wbnbBal.mul(CALL_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(tx.origin, callFee);

        uint256 rewardsFee = wbnbBal.mul(REWARDS_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(rewards, rewardsFee);
    }

    /**
     * @dev Swaps whatever {wbnb} it has for more {bifi}.
     */
    function swapRewards() internal {
        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(wbnbBal, 0, wbnbToBifiRoute, address(this), now.add(600));
    }

    /**
     * @dev Function to calculate the total underlaying {bifi} held by the strat.
     * It takes into account both the funds at hand, as the funds allocated in the RewardsPool.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfBifi().add(balanceOfPool());
    }

    /**
     * @dev It calculates how much {bifi} the contract holds.
     */
    function balanceOfBifi() public view returns (uint256) {
        return IERC20(bifi).balanceOf(address(this));
    }

    /**
     * @dev It calculates how much {bifi} the strategy has allocated in the RewardsPool
     */
    function balanceOfPool() public view returns (uint256) {
        return IRewardPool(rewards).balanceOf(address(this));
    }

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the 
     * vault, ready to be migrated to the new strat.
     */ 
    function retireStrat() external onlyOwner {
        panic();

        uint256 bifiBal = IERC20(bifi).balanceOf(address(this));
        IERC20(bifi).transfer(vault, bifiBal);
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from the OriginalGangster, leaving rewards behind
     */
    function panic() public onlyOwner {
        pause();
        IRewardPool(rewards).withdraw(balanceOfPool());
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public onlyOwner {
        _pause();

        IERC20(wbnb).safeApprove(unirouter, 0);
        IERC20(bifi).safeApprove(rewards, 0);
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external onlyOwner {
        _unpause();

        IERC20(wbnb).safeApprove(unirouter, uint(-1));
        IERC20(bifi).safeApprove(rewards, uint(-1));
    }
}
