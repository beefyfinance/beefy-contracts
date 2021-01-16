// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/common/IUniswapRouter.sol";
import "../../interfaces/pancake/IMasterChef.sol";

/**
 * @title Strategy Cake
 * @author sirbeefalot & superbeefyboy
 * @dev Implementation of a strategy to get yields from farming a Cake pool.
 * PancakeSwap is an automated market maker (“AMM”) that allows two tokens to be exchanged on the Binance Smart Chain.
 * It is fast, cheap, and allows anyone to participate.
 *
 * The strategy simply deposits whatever funds it receives from the vault into the MasterChef.
 * Rewards from the MasterChef can be regularly compounded.
 */
contract StrategyCake is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /**
     * @dev Tokens Used:
     * {wbnb} - Required for liquidity routing when doing swaps.
     * {cake} - Token that the strategy maximizes. The same token that users deposit in the vault.
     * {bifi} - BeefyFinance token, used to send funds to the treasury.
     */
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public cake = address(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    address constant public bifi = address(0xCa3F508B8e4Dd382eE878A314789373D80A5190A);

    /**
     * @dev Third Party Contracts:
     * {unirouter} - PancakeSwap unirouter
     * {masterchef} - MasterChef contract. Stake Cake, get rewards.
     */
    address constant public unirouter  = address(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    address constant public masterchef = address(0x73feaa1eE314F8c655E354234017bE2193C9E24E);

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
     * @dev Distribution of fees earned. This allocations relative to the % implemented on chargeFees().
     * Current implementation separates 6% for fees.
     *
     * {REWARDS_FEE} - 4% goes to BIFI holders through the {rewards} pool.
     * {CALL_FEE} - 0.5% goes to whoever executes the harvest function as gas subsidy.
     * {TREASURY_FEE} - 1.5% goes to the treasury.
     * {MAX_FEE} - Aux const used to safely calc the correct amounts.
     *
     * {WITHDRAWAL_FEE} - Fee taxed when a user withdraws funds. 10 === 0.1% fee.
     * {WITHDRAWAL_MAX} - Aux const used to safely calc the correct amounts.
     */
    uint constant public REWARDS_FEE  = 667;
    uint constant public CALL_FEE     = 83;
    uint constant public TREASURY_FEE = 250;
    uint constant public MAX_FEE      = 1000;

    uint constant public WITHDRAWAL_FEE = 10;
    uint constant public WITHDRAWAL_MAX = 10000;

    /**
     * @dev Routes we take to swap tokens using PancakeSwap.
     * {cakeToWbnbRoute} - Route we take to go from {cake} into {wbnb}.
     * {wbnbToBifiRoute} - Route we take to go from {wbnb} into {bifi}.
     */
    address[] public cakeToWbnbRoute = [cake, wbnb];
    address[] public wbnbToBifiRoute = [wbnb, bifi];

    /**
     * @dev Initializes the strategy with the token that it will look to maximize.
     * @param _vault Address of parent vault
     */
    constructor(address _vault) public {
        vault = _vault;

        IERC20(cake).safeApprove(unirouter, uint(-1));
        IERC20(wbnb).safeApprove(unirouter, uint(-1));
        IERC20(cake).safeApprove(masterchef, uint(-1));
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * It deposits cake in the MasterChef to earn rewards in cake.
     */
    function deposit() public whenNotPaused {
        uint256 cakeBal = IERC20(cake).balanceOf(address(this));

        if (cakeBal > 0) {
            IMasterChef(masterchef).enterStaking(cakeBal);
        }
    }

    /**
     * @dev It withdraws {cake} from the MasterChef and sends it to the vault.
     * @param _amount How much {cake} to withdraw.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 cakeBal = IERC20(cake).balanceOf(address(this));

        if (cakeBal < _amount) {
            IMasterChef(masterchef).leaveStaking(_amount.sub(cakeBal));
            cakeBal = IERC20(cake).balanceOf(address(this));
        }

        if (cakeBal > _amount) {
            cakeBal = _amount;    
        }
        
        if (tx.origin == owner()) {
            IERC20(cake).safeTransfer(vault, cakeBal); 
        } else {
            uint256 withdrawalFee = cakeBal.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
            IERC20(cake).safeTransfer(vault, cakeBal.sub(withdrawalFee)); 
        }
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * 1. It claims rewards from the MasterChef
     * 3. It charges the system fee and sends it to BIFI stakers.
     * 4. It re-invests the remaining profits.
     */
    function harvest() external whenNotPaused {
        require(!Address.isContract(msg.sender), "!contract");
        IMasterChef(masterchef).leaveStaking(0);
        chargeFees();
        deposit();
    }

    /**
     * @dev Takes out 6% as system fees from the rewards. 
     * 0.5% -> Call Fee
     * 1.5% -> Treasury fee
     * 4.0% -> BIFI Holders
     */
    function chargeFees() internal {
        uint256 toWbnb = IERC20(cake).balanceOf(address(this)).mul(6).div(100);
        IUniswapRouter(unirouter).swapExactTokensForTokens(toWbnb, 0, cakeToWbnbRoute, address(this), now.add(600));
    
        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));
        
        uint256 callFee = wbnbBal.mul(CALL_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(msg.sender, callFee);
        
        uint256 treasuryHalf = wbnbBal.mul(TREASURY_FEE).div(MAX_FEE).div(2);
        IERC20(wbnb).safeTransfer(treasury, treasuryHalf);
        IUniswapRouter(unirouter).swapExactTokensForTokens(treasuryHalf, 0, wbnbToBifiRoute, treasury, now.add(600));
        
        uint256 rewardsFee = wbnbBal.mul(REWARDS_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(rewards, rewardsFee);
    }

    /**
     * @dev Function to calculate the total underlaying {cake} held by the strat.
     * It takes into account both the funds in hand, as the funds allocated in the MasterChef.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfCake().add(balanceOfPool());
    }

    /**
     * @dev It calculates how much {cake} the contract holds.
     */
    function balanceOfCake() public view returns (uint256) {
        return IERC20(cake).balanceOf(address(this));
    }

    /**
     * @dev It calculates how much {cake} the strategy has allocated in the MasterChef
     */
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount, ) = IMasterChef(masterchef).userInfo(0, address(this));
        return _amount;
    }

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the 
     * vault, ready to be migrated to the new strat.
     */ 
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IMasterChef(masterchef).emergencyWithdraw(0);

        uint256 cakeBal = IERC20(cake).balanceOf(address(this));
        IERC20(cake).transfer(vault, cakeBal);
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from the MasterChef, leaving rewards behind
     */
    function panic() external onlyOwner {
        pause();
        IMasterChef(masterchef).emergencyWithdraw(0);
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public onlyOwner {
        _pause();

        IERC20(cake).safeApprove(unirouter, 0);
        IERC20(wbnb).safeApprove(unirouter, 0);
        IERC20(cake).safeApprove(masterchef, 0);
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external onlyOwner {
        _unpause();

        IERC20(cake).safeApprove(unirouter, uint(-1));
        IERC20(wbnb).safeApprove(unirouter, uint(-1));
        IERC20(cake).safeApprove(masterchef, uint(-1));
    }
}