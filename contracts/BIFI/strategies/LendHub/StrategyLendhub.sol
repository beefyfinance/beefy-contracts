// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/common/IUniswapRouter.sol";
import "../../interfaces/lendhub/IComptroller.sol";
import "../../interfaces/venus/IVToken.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";


// Lendhub Lending Strategy 
contract StrategyLendhub is StratManager, FeeManager  {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // Tokens Used
    address constant public lhb = address(0x8F67854497218043E1f72908FFE38D0Ed7F24721);
    address constant public wht = address(0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F);
    address constant public usdt = address(0xa71EdC38d189767582C38A3145b5873052c3e47a);
    address public itoken;
    address public want;

    // Third Party Contracts
    address constant public unitroller = address(0x6537d6307ca40231939985BCF7D83096Dd1B4C09);

    // Routes
    address[] public lhbToWhtRoute = [lhb, wht];
    address[] public lhbToWantRoute;

    // Leverage Rates
    uint256 public borrowRate;
    uint256 public borrowDepth;
    uint256 public minLeverage;
    uint256 constant public BORROW_RATE_MAX = 58;
    uint256 constant public BORROW_DEPTH_MAX = 10;

    // Deposited Balance
    uint256 public depositedBalance;

    /**
     * @dev Helps to differentiate borrowed funds that shouldn't be used in functions like 'deposit()'
     * as they're required to deleverage correctly.  
     */
    uint256 public reserves = 0;

    // Events
    event StratHarvest(address indexed harvester);
    event StratRebalance(uint256 _borrowRate, uint256 _borrowDepth);

    constructor( 
        address _itoken, 
        uint256 _borrowRate, 
        uint256 _borrowDepth, 
        uint256 _minLeverage, 
        address[] memory _markets,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
      )  StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        vault = _vault;
        itoken = _itoken;
        want = IVToken(_itoken).underlying();
        minLeverage = _minLeverage;
        borrowRate = _borrowRate;
        borrowDepth = _borrowDepth;

        lhbToWantRoute = [lhb, usdt, want];

        _giveAllowances();

        IComptroller(unitroller).enterMarkets(_markets);
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
            IVToken(itoken).mint(_amount);
            _amount = _amount.mul(borrowRate).div(100);
            IVToken(itoken).borrow(_amount);
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
        uint256 borrowBal = IVToken(itoken).borrowBalanceCurrent(address(this));

        while (wantBal < borrowBal) {
            IVToken(itoken).repayBorrow(wantBal);

            borrowBal = IVToken(itoken).borrowBalanceCurrent(address(this));
            uint256 targetUnderlying = borrowBal.mul(100).div(borrowRate);
            uint256 balanceOfUnderlying = IVToken(itoken).balanceOfUnderlying(address(this));

            IVToken(itoken).redeemUnderlying(balanceOfUnderlying.sub(targetUnderlying));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        IVToken(itoken).repayBorrow(uint256(-1));

        uint256 itokenBal = IERC20(itoken).balanceOf(address(this));
        IVToken(itoken).redeem(itokenBal);

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
        IVToken(itoken).repayBorrow(wantBal);

        uint256 borrowBal = IVToken(itoken).borrowBalanceCurrent(address(this));
        uint256 targetUnderlying = borrowBal.mul(100).div(_borrowRate);
        uint256 balanceOfUnderlying = IVToken(itoken).balanceOfUnderlying(address(this));

        IVToken(itoken).redeemUnderlying(balanceOfUnderlying.sub(targetUnderlying));
        
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

        IComptroller(unitroller).claimComp(address(this));
        chargeFees();
        _swapRewards();
        deposit();

        emit StratHarvest(msg.sender);
    }

    // performance fees
    function chargeFees() internal {
        uint256 toWht = IERC20(lhb).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouter(unirouter).swapExactTokensForTokens(toWht, 0, lhbToWhtRoute, address(this), now.add(600));
        
        uint whtFeeBal = IERC20(wht).balanceOf(address(this));

        uint256 callFeeAmount = whtFeeBal.mul(callFee).div(MAX_FEE);
        IERC20(wht).safeTransfer(msg.sender, callFeeAmount);

        uint256 beefyFeeAmount = whtFeeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(wht).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = whtFeeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wht).safeTransfer(strategist, strategistFee);
    }

    /**
     * @dev Swaps {venus} rewards earned for more {want}.
     */
    function _swapRewards() internal {
        uint256 lhbBal = IERC20(lhb).balanceOf(address(this));
        IUniswapRouter(unirouter).swapExactTokensForTokens(lhbBal, 0, lhbToWantRoute, address(this), now.add(600));
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

        uint256 fee = wantBal.mul(withdrawalFee).div(WITHDRAWAL_MAX);
        IERC20(want).safeTransfer(vault, wantBal.sub(fee));

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
        uint256 supplyBal = IVToken(itoken).balanceOfUnderlying(address(this));
        uint256 borrowBal = IVToken(itoken).borrowBalanceCurrent(address(this));
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

   // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        _deleverage();
        pause();
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

    function _giveAllowances() internal {
        IERC20(want).safeApprove(itoken, uint256(-1));
        IERC20(wht).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(itoken, 0);
        IERC20(wht).safeApprove(unirouter, 0);
    }
} 