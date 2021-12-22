// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/1inch/IGovMothership.sol";
import "../../interfaces/1inch/IMooniswap.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../../interfaces/common/IUniswapRouter.sol";
import "../../interfaces/common/IWBNB.sol";
import "../../utils/GasThrottler.sol";

/**
 * @dev Implementation of a strategy to get yields from staking 1Inch in Gov pool.
 */
contract Strategy1Inch is Ownable, Pausable, GasThrottler {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /**
     * @dev Tokens Used:
     * {wbnb} - Required for liquidity routing when doing swaps.
     * {inch} - Token that the strategy maximizes. The same token that users deposit in the vault.
     * {bnb}  - 0 address representing BNB(ETH) native token in 1Inch LP pairs.
     * {bifi} - BeefyFinance token, used to send funds to the treasury.
     * {lpPair} - 1Inch-BNB LP pair to swap {inch} into {bnb} for paying fees.
     */
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public inch = address(0x111111111117dC0aa78b770fA6A738034120C302);
    address constant public bifi = address(0xCa3F508B8e4Dd382eE878A314789373D80A5190A);
    address constant public bnb  = address(0x0000000000000000000000000000000000000000);
    address constant public lpPair = address(0xdaF66c0B7e8E2FC76B15B07AD25eE58E04a66796);

    /**
     * @dev Third Party Contracts:
     * {unirouter} - PancakeSwap unirouter
     * {govMothership} - GovernanceMothership contract to stake and unstake 1Inch
     * {govRewards} - GovernanceRewards contract to claim rewards
     */
    address constant public unirouter     = address(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    address constant public govMothership = address(0x73F0a6927A3c04E679074e70DFb9105F453e799D);
    address constant public govRewards    = address(0x59a0A6d73e6a5224871f45E6d845ce1574063ADe);

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
     * {REWARDS_FEE} - 3% goes to BIFI holders through the {rewards} pool.
     * {CALL_FEE} - 0.5% goes to whoever executes the harvest function as gas subsidy.
     * {TREASURY_FEE} - 0.5% goes to the treasury.
     * {STRATEGIST_FEE} - 0.5% goes to the strategist.
     * {MAX_FEE} - Aux const used to safely calc the correct amounts.
     *
     * {WITHDRAWAL_FEE} - Fee taxed when a user withdraws funds. 10 === 0.1% fee.
     * {WITHDRAWAL_MAX} - Aux const used to safely calc the correct amounts.
     */
    uint constant public REWARDS_FEE    = 665;
    uint constant public CALL_FEE       = 111;
    uint constant public TREASURY_FEE   = 112;
    uint constant public STRATEGIST_FEE = 112;
    uint constant public MAX_FEE        = 1000;

    uint constant public WITHDRAWAL_FEE = 10;
    uint constant public WITHDRAWAL_MAX = 10000;

    /**
     * @dev Routes we take to swap tokens using PancakeSwap.
     * {wbnbToBifiRoute} - Route we take to go from {wbnb} into {bifi}.
     */
    address[] public wbnbToBifiRoute = [wbnb, bifi];

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);

    /**
     * @dev Initializes the strategy with the token to maximize.
     */
    constructor(address _vault, address _strategist) public {
        vault = _vault;
        strategist = _strategist;

        IERC20(inch).safeApprove(govMothership, uint(-1));
        IERC20(inch).safeApprove(lpPair, uint(-1));
        IERC20(wbnb).safeApprove(unirouter, uint(-1));
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * It deposits {inch} in the Gov pool to earn rewards in {inch}.
     */
    function deposit() public whenNotPaused {
        uint256 inchBal = IERC20(inch).balanceOf(address(this));

        if (inchBal > 0) {
            IGovMothership(govMothership).stake(inchBal);
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     * It withdraws {inch} from the Gov pool.
     * The available {inch} minus fees is returned to the vault.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 inchBal = IERC20(inch).balanceOf(address(this));

        if (inchBal < _amount) {
            IGovMothership(govMothership).unstake(_amount.sub(inchBal));
            inchBal = IERC20(inch).balanceOf(address(this));
        }

        if (inchBal > _amount) {
            inchBal = _amount;
        }

        if (tx.origin == owner()) {
            IERC20(inch).safeTransfer(vault, inchBal);
        } else {
            uint256 withdrawalFee = inchBal.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
            IERC20(inch).safeTransfer(vault, inchBal.sub(withdrawalFee));
        }
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * 1. It claims rewards from the Gov pool
     * 3. It charges the system fee and sends it to BIFI stakers.
     * 4. It re-invests the remaining profits.
     */
    function harvest() external whenNotPaused gasThrottle {
        require(!Address.isContract(msg.sender), "!contract");
        IRewardPool(govRewards).getReward();
        chargeFees();
        deposit();

        emit StratHarvest(msg.sender);
    }

    /**
     * @dev Takes out 4.5% as system fees from the rewards.
     * 0.5% -> Call Fee
     * 0.5% -> Treasury fee
     * 0.5% -> Strategist fee
     * 3.0% -> BIFI Holders
     */
    function chargeFees() internal {
        uint256 toWbnb = IERC20(inch).balanceOf(address(this)).mul(45).div(1000);
        IMooniswap(lpPair).swap(inch, bnb, toWbnb, 1, address(this));

        IWBNB(wbnb).deposit{value: address(this).balance}();

        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));

        uint256 callFee = wbnbBal.mul(CALL_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(tx.origin, callFee);

        uint256 treasuryHalf = wbnbBal.mul(TREASURY_FEE).div(MAX_FEE).div(2);
        IERC20(wbnb).safeTransfer(treasury, treasuryHalf);
        IUniswapRouter(unirouter).swapExactTokensForTokens(treasuryHalf, 0, wbnbToBifiRoute, treasury, now.add(600));

        uint256 rewardsFee = wbnbBal.mul(REWARDS_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(rewards, rewardsFee);

        uint256 strategistFee = wbnbBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(strategist, strategistFee);
    }

    /**
     * @dev Function to calculate the total underlying {inch} held by the strat.
     * It takes into account both the funds in hand, as the funds allocated in Gov pool.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfInch().add(balanceOfPool());
    }

    /**
     * @dev It calculates how much {inch} the contract holds.
     */
    function balanceOfInch() public view returns (uint256) {
        return IERC20(inch).balanceOf(address(this));
    }

    /**
     * @dev It calculates how much {inch} the strategy has allocated in the Gov pool
     */
    function balanceOfPool() public view returns (uint256) {
        return IGovMothership(govMothership).balanceOf(address(this));
    }

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the
     * vault, ready to be migrated to the new strat.
     */
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IGovMothership(govMothership).unstake(balanceOfPool());

        uint256 inchBal = IERC20(inch).balanceOf(address(this));
        IERC20(inch).transfer(vault, inchBal);
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from the Gov pool, leaving rewards behind
     */
    function panic() public onlyOwner {
        pause();
        IGovMothership(govMothership).unstake(balanceOfPool());
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public onlyOwner {
        _pause();

        IERC20(inch).safeApprove(govMothership, 0);
        IERC20(inch).safeApprove(lpPair, 0);
        IERC20(wbnb).safeApprove(unirouter, 0);
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external onlyOwner {
        _unpause();

        IERC20(inch).safeApprove(govMothership, uint(-1));
        IERC20(inch).safeApprove(lpPair, uint(-1));
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

    receive () external payable {}
}