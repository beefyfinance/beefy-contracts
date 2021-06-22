// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/bakery/IBakerySwapRouter.sol";
import "../../interfaces/bakery/IBakeryMaster.sol";

/**
 * @dev Implementation of a strategy to get yields from farming Bake in BakerySwap.
 */
contract StrategyBake is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /**
     * @dev Tokens Used:
     * {wbnb} - Required for liquidity routing when doing swaps.
     * {bake} - Token that the strategy maximizes. The same token that users deposit in the vault.
     * {bifi} - BeefyFinance token, used to send funds to the treasury.
     */
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public bake = address(0xE02dF9e3e622DeBdD69fb838bB799E3F168902c5);
    address constant public bifi = address(0xCa3F508B8e4Dd382eE878A314789373D80A5190A);

    /**
     * @dev Third Party Contracts:
     * {unirouter} - BakerySwap unirouter
     * {bakeryMaster} - BakeryMaster contract. Stake Tokens, get rewards.
     */
    address constant public unirouter  = address(0xCDe540d7eAFE93aC5fE6233Bee57E1270D3E330F);
    address constant public bakeryMaster = address(0x20eC291bB8459b6145317E7126532CE7EcE5056f);

    /**
     * @dev Beefy Contracts:
     * {rewards} - Reward pool where the strategy fee earnings will go.
     * {treasury} - Address of the BeefyFinance treasury
     * {vault} - Address of the vault that controls the strategy's funds.
     */
    address constant public rewards  = address(0x453D4Ba9a2D594314DF88564248497F7D74d6b2C);
    address constant public treasury = address(0x4A32De8c248533C28904b24B4cFCFE18E9F2ad01);
    address public vault;

    /**
     * @dev Distribution of fees earned. This allocations relative to the % implemented on doSplit().
     * Current implementation separates 4.5% for fees.
     *
     * {REWARDS_FEE} - 3.5% goes to BIFI holders through the {rewards} pool.
     * {CALL_FEE} - 0.5% goes to whoever executes the harvest function as gas subsidy.
     * {TREASURY_FEE} - 0.5% goes to the treasury.
     * {MAX_FEE} - Aux const used to safely calc the correct amounts.
     *
     * {WITHDRAWAL_FEE} - Fee taxed when a user withdraws funds. 10 === 0.1% fee.
     * {WITHDRAWAL_MAX} - Aux const used to safely calc the correct amounts.
     */
    uint constant public REWARDS_FEE  = 777;
    uint constant public CALL_FEE     = 111;
    uint constant public TREASURY_FEE = 112;
    uint constant public MAX_FEE      = 1000;

    uint constant public WITHDRAWAL_FEE = 10;
    uint constant public WITHDRAWAL_MAX = 10000;

    /**
     * @dev Routes we take to swap tokens using BakerySwap.
     * {bakeToWbnbRoute} - Route we take to go from {bake} into {wbnb}.
     * {wbnbToBifiRoute} - Route we take to go from {wbnb} into {bifi}.
     */
    address[] public bakeToWbnbRoute = [bake, wbnb];
    address[] public wbnbToBifiRoute = [wbnb, bifi];

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);

    /**
     * @dev Initializes the strategy with the token that it will look to maximize.
     */
    constructor(address _vault) public {
        vault = _vault;

        IERC20(bake).safeApprove(unirouter, uint(-1));
        IERC20(wbnb).safeApprove(unirouter, uint(-1));
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * It deposits bake in the BakeryMaster to earn rewards in bake.
     */
    function deposit() public whenNotPaused {
        uint256 bakeBal = IERC20(bake).balanceOf(address(this));

        if (bakeBal > 0) {
            IERC20(bake).safeApprove(bakeryMaster, 0);
            IERC20(bake).safeApprove(bakeryMaster, bakeBal);
            IBakeryMaster(bakeryMaster).deposit(bake, bakeBal);
        }
    }

    /**
     * @dev It withdraws bake from the BakeryMaster and sends it to the vault.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 bakeBal = IERC20(bake).balanceOf(address(this));

        if (bakeBal < _amount) {
            IBakeryMaster(bakeryMaster).withdraw(bake, _amount.sub(bakeBal));
            bakeBal = IERC20(bake).balanceOf(address(this));
        }

        if (bakeBal > _amount) {
            bakeBal = _amount;    
        }
        
        uint256 withdrawalFee = bakeBal.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
        IERC20(bake).safeTransfer(vault, bakeBal.sub(withdrawalFee));
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * 1. It claims rewards from the BakeryMaster
     * 3. It charges the system fee and sends it to BIFI stakers.
     * 4. It re-invests the remaining profits.
     */
    function harvest() external whenNotPaused {
        require(!Address.isContract(msg.sender), "!contract");
        IBakeryMaster(bakeryMaster).deposit(bake, 0);
        chargeFees();
        deposit();

        emit StratHarvest(msg.sender);
    }

    /**
     * @dev Takes out 4.5% as system fees from the rewards. 
     * 0.5% -> Call Fee
     * 0.5% -> Treasury fee
     * 3.5% -> BIFI Holders
     */
    function chargeFees() internal {
        uint256 toWbnb = IERC20(bake).balanceOf(address(this)).mul(45).div(1000);
        IBakerySwapRouter(unirouter).swapExactTokensForTokens(toWbnb, 0, bakeToWbnbRoute, address(this), now.add(600));
    
        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));
        
        uint256 callFee = wbnbBal.mul(CALL_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(msg.sender, callFee);
        
        uint256 treasuryHalf = wbnbBal.mul(TREASURY_FEE).div(MAX_FEE).div(2);
        IERC20(wbnb).safeTransfer(treasury, treasuryHalf);
        IBakerySwapRouter(unirouter).swapExactTokensForTokens(treasuryHalf, 0, wbnbToBifiRoute, treasury, now.add(600));
        
        uint256 rewardsFee = wbnbBal.mul(REWARDS_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(rewards, rewardsFee);
    }

    /**
     * @dev Function to calculate the total underlaying {bake} held by the strat.
     * It takes into account both the funds in hand, as the funds allocated in the BakeryMaster.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfBake().add(balanceOfPool());
    }

    /**
     * @dev It calculates how much {bake} the contract holds.
     */
    function balanceOfBake() public view returns (uint256) {
        return IERC20(bake).balanceOf(address(this));
    }

    /**
     * @dev It calculates how much {bake} the strategy has allocated in the BakeryMaster
     */
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount, ) = IBakeryMaster(bakeryMaster).poolUserInfoMap(bake, address(this));
        return _amount;
    }

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the 
     * vault, ready to be migrated to the new strat.
     */ 
    function retireStrat() external onlyOwner {
        panic();

        uint256 bakeBal = IERC20(bake).balanceOf(address(this));
        IERC20(bake).transfer(vault, bakeBal);
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from the BakeryMaster, leaving rewards behind
     */
    function panic() public onlyOwner {
        pause();
        IBakeryMaster(bakeryMaster).emergencyWithdraw(bake);
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public onlyOwner {
        _pause();

        IERC20(bake).safeApprove(unirouter, 0);
        IERC20(wbnb).safeApprove(unirouter, 0);
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external onlyOwner {
        _unpause();

        IERC20(bake).safeApprove(unirouter, uint(-1));
        IERC20(wbnb).safeApprove(unirouter, uint(-1));
    }
}