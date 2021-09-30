// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/common/IUniswapRouter.sol";
import "../../interfaces/venus/IUnitroller.sol";
import "../../interfaces/venus/IVToken.sol";

/**
 * @title Strategy Venus XVS
 * @author sirbeefalot & superbeefyboy
 * @dev It maximizes yields doing leveraged lending with XVS on Venus.
 */
contract StrategyVenusXVS is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /**
     * @dev Tokens Used:
     * {venus}   - Token earned through farming.
     * {wbnb}    - Required for liquidity routing when doing swaps. 
     * {bifi}    - BeefyFinance token, used to send funds to the treasury.
     * {vtoken}  - Venus Token. We interact with it to mint/redem/borrow/repay the loan.
     * {want}    - Token that the strategy maximizes. 
     */
    address constant public venus = address(0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63);
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public bifi = address(0xCa3F508B8e4Dd382eE878A314789373D80A5190A);
    address public vtoken;
    address public want;

    /**
     * @dev Third Party Contracts:
     * {unirouter}  - Pancakeswap unirouter. Has the most liquidity for {venus}.
     * {unitroller} - Controller contract for the {venus} rewards.
     */
    address constant public unirouter  = address(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    address constant public unitroller = address(0xfD36E2c2a6789Db23113685031d7F16329158384);

    /**
     * @dev Beefy Contracts:
     * {rewards}  - Reward pool where the strategy fee earnings will go.
     * {treasury} - Address of the BeefyFinance treasury
     * {vault}    - Address of the vault that controls the strategy's funds.
     * {strategist} - Address of the strategy author/deployer where strategist fee will go.
     */
    address constant public rewards  = address(0x453D4Ba9a2D594314DF88564248497F7D74d6b2C);
    address constant public treasury = address(0x4A32De8c248533C28904b24B4cFCFE18E9F2ad01);
    address public vault;
    address public strategist;

    /**
     * @dev Distribution of fees earned. This allocations relative to the % implemented on chargeFees().
     * Current implementation separates 5.0% for fees.
     *
     * {REWARDS_FEE} - 3% goes to BIFI holders through the {rewards} pool.
     * {CALL_FEE} - 1% goes to whoever executes the harvest function as gas subsidy.
     * {TREASURY_FEE} - 0.5% goes to the treasury.
     * {STRATEGIST_FEE} - 0.5% goes to the strategist.
     * {MAX_FEE} - Aux const used to safely calc the correct amounts.
     *
     * {WITHDRAWAL_FEE} - Fee taxed when a user withdraws funds. 5 === 0.05% fee.
     * {WITHDRAWAL_MAX} - Aux const used to safely calc the correct amounts.
     */
    uint256 constant public REWARDS_FEE    = 600;
    uint256 constant public CALL_FEE       = 200;
    uint256 constant public TREASURY_FEE   = 100;
    uint256 constant public STRATEGIST_FEE = 100;
    uint256 constant public MAX_FEE        = 1000;

    uint256 constant public WITHDRAWAL_FEE = 5;
    uint256 constant public WITHDRAWAL_MAX = 10000;

    /**
     * @dev Routes we take to swap tokens using the {unirouter}.
     * {venusToWbnbRoute} - Route we take to go from {venus} into {wbnb}.
     * {wbnbToBifiRoute}  - Route we take to go from {wbnb} into {bifi}.
     */
    address[] public venusToWbnbRoute = [venus, wbnb];
    address[] public wbnbToBifiRoute = [wbnb, bifi];

    /**
     * @dev Variables that can be changed to config profitability and risk:
     * {borrowRate}          - What % of our collateral do we borrow per leverage level.
     * {borrowDepth}         - How many levels of leverage do we take. 
     * {minLeverage}         - The minimum amount of collateral required to leverage.
     * {BORROW_RATE_MAX}     - A limit on how much we can push borrow risk.
     * {BORROW_DEPTH_MAX}    - A limit on how many steps we can leverage.
     */
    uint256 public borrowRate;
    uint256 public borrowDepth;
    uint256 public minLeverage;
    uint256 constant public BORROW_RATE_MAX = 58;
    uint256 constant public BORROW_DEPTH_MAX = 10;

    /** 
     * @dev We keep and update a cache of the strat's {want} deposited in venus. Contract
     * functions that use this value always update it first. We use it to keep the UI helper
     * functions as view only.  
     */
    uint256 public depositedBalance;

    /**
     * @dev Helps to differentiate borrowed funds that shouldn't be used in functions like 'deposit()'
     * as they're required to deleverage correctly.  
     */
    uint256 public reserves = 0;

    /**
     * @dev Events that the contract emits
     */
    event StratHarvest(address indexed harvester);
    event StratRebalance(uint256 _borrowRate, uint256 _borrowDepth);

    /**
     * @notice Initializes the strategy
     * @param _vault Address of the vault that will manage the strat.
     * @param _vtoken Address of the vtoken that we will interact with.
     * @param _borrowRate Initial borrow rate used.
     * @param _borrowDepth Initial borow depth used.
     * @param _minLeverage Minimum amount that the '_leverage' function will actually leverage. 
     * @param _markets Array with a single element being the target vtoken address.
     */
    constructor(
        address _vault, 
        address _vtoken, 
        uint256 _borrowRate, 
        uint256 _borrowDepth, 
        uint256 _minLeverage, 
        address[] memory _markets
    ) public {
        vault = _vault;
        vtoken = _vtoken;
        want = IVToken(_vtoken).underlying();
        minLeverage = _minLeverage;
        borrowRate = _borrowRate;
        borrowDepth = _borrowDepth;
        strategist = msg.sender;

        IERC20(want).safeApprove(vtoken, uint(-1));
        IERC20(venus).safeApprove(unirouter, uint(-1));
        IERC20(wbnb).safeApprove(unirouter, uint(-1));

        IUnitroller(unitroller).enterMarkets(_markets);
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault. It does {borrowDepth} 
     * levels of compound lending. It also updates the helper {depositedBalance} variable.
     */
    function deposit() public whenNotPaused {
        uint256 wantBal = availableWant();
        
        if (wantBal > 0) {
            _leverage(wantBal);
        }

        updateBalance();
    }

    /**
     * @dev Repeatedly supplies and borrows {want} following the configured {borrowRate} and {borrowDepth}
     * @param _amount amount of {want} to leverage
     */
    function _leverage(uint256 _amount) internal {
        if (_amount < minLeverage) { return; }

        for (uint i = 0; i < borrowDepth; i++) {
            IVToken(vtoken).mint(_amount);
            _amount = _amount.mul(borrowRate).div(100);
            IVToken(vtoken).borrow(_amount);
        }

        reserves = reserves.add(_amount);
    } 

    /**
     * @dev Incrementally alternates between paying part of the debt and withdrawing part of the supplied 
     * collateral. Continues to do this until it repays the entire debt and withdraws all the supplied {want} 
     * from the system
     */
    function _deleverage() internal {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        uint256 borrowBal = IVToken(vtoken).borrowBalanceCurrent(address(this));

        while (wantBal < borrowBal) {
            IVToken(vtoken).repayBorrow(wantBal);

            borrowBal = IVToken(vtoken).borrowBalanceCurrent(address(this));
            uint256 targetUnderlying = borrowBal.mul(100).div(borrowRate);
            uint256 balanceOfUnderlying = IVToken(vtoken).balanceOfUnderlying(address(this));

            IVToken(vtoken).redeemUnderlying(balanceOfUnderlying.sub(targetUnderlying));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        IVToken(vtoken).repayBorrow(uint256(-1));

        uint256 vtokenBal = IERC20(vtoken).balanceOf(address(this));
        IVToken(vtoken).redeem(vtokenBal);

        reserves = 0;
    }

    /**
     * @dev Extra safety measure that allows us to manually unwind one level. In case we somehow get into 
     * as state where the cost of unwinding freezes the system. We can manually unwind a few levels 
     * with this function and then 'rebalance()' with new {borrowRate} and {borrowConfig} values. 
     * @param _borrowRate configurable borrow rate in case it's required to unwind successfully
     */
    function deleverageOnce(uint _borrowRate) external onlyOwner {
        require(_borrowRate <= BORROW_RATE_MAX, "!safe");

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IVToken(vtoken).repayBorrow(wantBal);

        uint256 borrowBal = IVToken(vtoken).borrowBalanceCurrent(address(this));
        uint256 targetUnderlying = borrowBal.mul(100).div(_borrowRate);
        uint256 balanceOfUnderlying = IVToken(vtoken).balanceOfUnderlying(address(this));

        IVToken(vtoken).redeemUnderlying(balanceOfUnderlying.sub(targetUnderlying));
        
        updateBalance();

        wantBal = IERC20(want).balanceOf(address(this));
        reserves = wantBal;
    }

    /**xw
     * @dev Updates the risk profile and rebalances the vault funds accordingly.
     * @param _borrowRate percent to borrow on each leverage level.
     * @param _borrowDepth how many levels to leveraxge the funds.
     */
    function rebalance(uint256 _borrowRate, uint256 _borrowDepth) external onlyOwner {
        require(_borrowRate <= BORROW_RATE_MAX, "!rate");
        require(_borrowDepth <= BORROW_DEPTH_MAX, "!depth");

        _deleverage();
        borrowRate = _borrowRate;
        borrowDepth = _borrowDepth;

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        _leverage(wantBal);

        StratRebalance(_borrowRate, _borrowDepth);
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * 1. It claims {venus} rewards from the Unitroller.
     * 3. It charges the system fee and sends it to BIFI stakers.
     * 4. It swaps the remaining rewards into more {want}.
     * 4. It re-invests the remaining profits.
     */
    function harvest() external whenNotPaused {
        require(!Address.isContract(msg.sender), "!contract");

        IUnitroller(unitroller).claimVenus(address(this));
        _chargeFees();
        deposit();

        emit StratHarvest(msg.sender);
    }

    /**
     * @dev Takes out 5.0% as system fees from the rewards.
     * 1% -> Call Fee
     * 0.5% -> Treasury fee
     * 0.5% -> Strategist fee
     * 3% -> BIFI Holders
     */
    function _chargeFees() internal {
        uint256 toWbnb = IERC20(venus).balanceOf(address(this)).mul(50).div(1000);
        IUniswapRouter(unirouter).swapExactTokensForTokens(toWbnb, 0, venusToWbnbRoute, address(this), now.add(600));

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
     * @dev Withdraws funds and sends them back to the vault. It deleverages from venus first,
     * and then deposits again after the withdraw to make sure it mantains the desired ratio. 
     * @param _amount How much {want} to withdraw.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = availableWant();

        if (wantBal < _amount) {
            _deleverage();
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;    
        }

        uint256 withdrawalFee = wantBal.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
        IERC20(want).safeTransfer(vault, wantBal.sub(withdrawalFee));

        if (!paused()) {
            _leverage(availableWant());
        }
  
        updateBalance();
    }

    /**
     * @dev It helps mantain a cached version of the {want} deposited in venus. 
     * We use it to be able to keep the vault's 'balance()' function and 
     * 'getPricePerFullShare()' with view visibility. 
     */
    function updateBalance() public {
        uint256 supplyBal = IVToken(vtoken).balanceOfUnderlying(address(this));
        uint256 borrowBal = IVToken(vtoken).borrowBalanceCurrent(address(this));
        depositedBalance = supplyBal.sub(borrowBal);
    }

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the 
     * vault, ready to be migrated to the new strat.
     */ 
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        panic();

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from the Venus Platform.
     */
    function panic() public onlyOwner {        
        _deleverage();
        updateBalance();
        pause();
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public onlyOwner {
        _pause();

        IERC20(want).safeApprove(vtoken, 0);
        IERC20(venus).safeApprove(unirouter, 0);
        IERC20(wbnb).safeApprove(unirouter, 0);
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external onlyOwner {
        _unpause();

        IERC20(want).safeApprove(vtoken, uint(-1));
        IERC20(venus).safeApprove(unirouter, uint(-1));
        IERC20(wbnb).safeApprove(unirouter, uint(-1));
    }

    /**
     * @dev Function to calculate the total underlaying {want} held by the strat.
     * It takes into account both the funds at hand, and the funds allocated in the {vtoken} contract.
     * It uses a cache of the balances stored in {depositedBalance} to enable a few UI helper functions
     * to exist. Sensitive functions should call 'updateBalance()' first to make sure the data is up to date.
     * @return total {want} held by the strat.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfStrat().add(depositedBalance);
    }

    /**
     * @notice Balance in strat contract
     * @return how much {want} the contract holds.
     */
    function balanceOfStrat() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /**
     * @dev Required for various functions that need to deduct {reserves} from total {want}.
     * @return how much {want} the hontract holds without reserves     ∫
     */
     function availableWant() public view returns (uint256) {
         uint256 wantBal = IERC20(want).balanceOf(address(this));
         return wantBal.sub(reserves);
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