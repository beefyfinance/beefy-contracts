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
import "../../interfaces/mdex/ISwapMining.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";


//Lendhub Strategy 
contract StrategyLendhub is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public wht = address(0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F);
    address constant public usdt = address(0xa71EdC38d189767582C38A3145b5873052c3e47a);
    address constant public output = address(0x8F67854497218043E1f72908FFE38D0Ed7F24721);
    address constant public mdx = address(0x25D2e80cB6B86881Fd7e07dd263Fb79f4AbE033c);
    address public want;
    address public iToken;

    // Third party contracts
    address constant public comptroller = address(0x6537d6307ca40231939985BCF7D83096Dd1B4C09);
    address constant public swapContract = address(0x7373c42502874C88954bDd6D50b53061F018422e);

    // Routes
    address[] public outputToWhtRoute = [output, wht];
    address[] public mdxToOutputRoute = [mdx, wht, output];
    address[] public outputToWantRoute;

    /**
     * @dev Variables that can be changed to config profitability and risk:
     * {borrowRate}          - What % of our collateral do we borrow per leverage level.
     * {borrowRateMax}       - A limit on how much we can push borrow risk.
     * {borrowDepth}         - How many levels of leverage do we take.
     * {minLeverage}         - The minimum amount of collateral required to leverage.
     * {BORROW_DEPTH_MAX}    - A limit on how many steps we can leverage.
     * {INTEREST_RATE_MODE}  - The type of borrow debt. Stable: 1, Variable: 2.
     */
    uint256 public borrowRate;
    uint256 public borrowRateMax;
    uint256 public borrowDepth;
    uint256 public minLeverage;
    uint256 constant public BORROW_DEPTH_MAX = 10;

    /**
     * @dev Helps to differentiate borrowed funds that shouldn't be used in functions like 'deposit()'
     * as they're required to deleverage correctly.  
     */
    uint256 public reserves = 0;
    
    uint256 public balanceOfPool;

    /**
     * @dev Events that the contract emits
     */
    event StratHarvest(address indexed harvester);
    event StratRebalance(uint256 _borrowRate, uint256 _borrowDepth);

    constructor(
        address _iToken,
        uint256 _borrowRate,
        uint256 _borrowRateMax,
        uint256 _borrowDepth,
        uint256 _minLeverage,
        address[] memory _markets,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        iToken = _iToken;
        want = IVToken(_iToken).underlying();
        borrowRate = _borrowRate;
        borrowRateMax = _borrowRateMax;
        borrowDepth = _borrowDepth;
        minLeverage = _minLeverage;

        outputToWantRoute = [output, usdt, want];

        _giveAllowances();
        
        IComptroller(comptroller).enterMarkets(_markets);
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = availableWant();

        if (wantBal > 0) {
            _leverage(wantBal);
        }
        
    }

    /**
     * @dev Repeatedly supplies and borrows {want} following the configured {borrowRate} and {borrowDepth}
     * @param _amount amount of {want} to leverage
     */
    function _leverage(uint256 _amount) internal {
        if (_amount < minLeverage) { return; }

        for (uint i = 0; i < borrowDepth; i++) {
            IVToken(iToken).mint(_amount);
            _amount = _amount.mul(borrowRate).div(100);
            IVToken(iToken).borrow(_amount);
        }

        reserves = reserves.add(_amount);
        
        updateBalance();
    }


    /**
     * @dev Incrementally alternates between paying part of the debt and withdrawing part of the supplied
     * collateral. Continues to do this until it repays the entire debt and withdraws all the supplied {want}
     * from the system
     */
    function _deleverage() internal {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        uint256 borrowBal = IVToken(iToken).borrowBalanceCurrent(address(this));

        while (wantBal < borrowBal) {
            IVToken(iToken).repayBorrow(wantBal);

            borrowBal = IVToken(iToken).borrowBalanceCurrent(address(this));
            uint256 targetSupply = borrowBal.mul(100).div(borrowRate);
        
            uint256 supplyBal = IVToken(iToken).balanceOfUnderlying(address(this));
            IVToken(iToken).redeemUnderlying(supplyBal.sub(targetSupply));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        IVToken(iToken).repayBorrow(uint256(-1));
        
        uint256 iTokenBal = IERC20(iToken).balanceOf(address(this));
        IVToken(iToken).redeem(iTokenBal);

        reserves = 0;
        
        updateBalance();
    }
    

    /**
     * @dev Extra safety measure that allows us to manually unwind one level. In case we somehow get into
     * as state where the cost of unwinding freezes the system. We can manually unwind a few levels
     * with this function and then 'rebalance()' with new {borrowRate} and {borrowConfig} values.
     * @param _borrowRate configurable borrow rate in case it's required to unwind successfully
     */
    function deleverageOnce(uint _borrowRate) external onlyManager {
        require(_borrowRate <= borrowRateMax, "!safe");

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IVToken(iToken).repayBorrow(wantBal);

        uint256 borrowBal = IVToken(iToken).borrowBalanceCurrent(address(this));
        uint256 targetSupply = borrowBal.mul(100).div(_borrowRate);
        
        uint256 supplyBal = IVToken(iToken).balanceOfUnderlying(address(this));
        IVToken(iToken).redeemUnderlying(supplyBal.sub(targetSupply));
        
        wantBal = IERC20(want).balanceOf(address(this));
        reserves = wantBal;
        
        updateBalance();
    }
    


    /**
     * @dev Updates the risk profile and rebalances the vault funds accordingly.
     * @param _borrowRate percent to borrow on each leverage level.
     * @param _borrowDepth how many levels to leverage the funds.
     */
    function rebalance(uint256 _borrowRate, uint256 _borrowDepth) external onlyManager {
        require(_borrowRate <= borrowRateMax, "!rate");
        require(_borrowDepth <= BORROW_DEPTH_MAX, "!depth");

        _deleverage();
        borrowRate = _borrowRate;
        borrowDepth = _borrowDepth;

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        _leverage(wantBal);

        StratRebalance(_borrowRate, _borrowDepth);
    }

    // compounds earnings and charges performance fee
    function harvest() external whenNotPaused {
        address[] memory markets = new address[](1);
        markets[0] = iToken;
        IComptroller(comptroller).claimComp(address(this), markets);
        chargeFees();
        swapRewards();
        deposit();

        emit StratHarvest(msg.sender);
    }

    // performance fees
    function chargeFees() internal {
        ISwapMining(swapContract).takerWithdraw();
        uint256 mdxClaim = IERC20(mdx).balanceOf(address(this));

        if (mdxClaim > 0) {
        IUniswapRouter(unirouter).swapExactTokensForTokens(mdxClaim, 0, mdxToOutputRoute, address(this), block.timestamp);
        }

        uint256 toWht = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouter(unirouter).swapExactTokensForTokens(toWht, 0, outputToWhtRoute, address(this), now);
        
        uint256 whtBal = IERC20(wht).balanceOf(address(this));

        uint256 callFeeAmount = whtBal.mul(callFee).div(MAX_FEE);
        IERC20(wht).safeTransfer(tx.origin, callFeeAmount);

        uint256 beefyFeeAmount = whtBal.mul(beefyFee).div(MAX_FEE);
        IERC20(wht).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = whtBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wht).safeTransfer(strategist, strategistFee);
    }

    // swap rewards to {want}
    function swapRewards() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        IUniswapRouter(unirouter).swapExactTokensForTokens(outputBal, 0, outputToWantRoute, address(this), now);
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

        if (tx.origin == owner() || paused()) {
            IERC20(want).safeTransfer(vault, wantBal);
        } else {
            uint256 withdrawalFeeAmount = wantBal.mul(withdrawalFee).div(WITHDRAWAL_MAX);
            IERC20(want).safeTransfer(vault, wantBal.sub(withdrawalFeeAmount));
        }

        if (!paused()) {
            _leverage(availableWant());
        }
    }

    /**
     * @dev Required for various functions that need to deduct {reserves} from total {want}.
     * @return how much {want} the contract holds without reserves
     */
    function availableWant() public view returns (uint256) {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        return wantBal.sub(reserves);
    }

    function beforeDeposit() external override {
        updateBalance();
    }
    
    // return supply and borrow balance
    function updateBalance() public {
        uint256 supplyBal = IVToken(iToken).balanceOfUnderlying(address(this));
        uint256 borrowBal = IVToken(iToken).borrowBalanceCurrent(address(this));
        balanceOfPool = supplyBal.sub(borrowBal);
    }


    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool);
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        _deleverage();

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

    function _giveAllowances() internal {
        IERC20(want).safeApprove(iToken, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
        IERC20(mdx).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(iToken, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(mdx).safeApprove(unirouter, 0);
    }
}