// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/bunny/IBunnyVault.sol";
import "../../utils/GasThrottler.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyBunnyCake is StratManager, FeeManager, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public bunny = address(0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51);
    address public want;

    // Third party contracts
    address constant public bunnyVault = address(0xEDfcB78e73f7bA6aD2D829bf5D462a0924da28eD);

    // Routes
    address[] public bunnyToWantRoute;
    address[] public wantToWbnbRoute;

    constructor(
        address _want,
        address _keeper, 
        address _strategist,
        address _unirouter,
        address _beefyFeeRecipient,
        address _vault
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient)  public {
        want = _want;

        bunnyToWantRoute = [bunny, wbnb, want];
        wantToWbnbRoute = [want, wbnb];

        _giveAllowances();
    }

    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IBunnyVault(bunnyVault).deposit(wantBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            IBunnyVault(bunnyVault).withdrawUnderlying(_amount.sub(wantBal));
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;    
        }
        
        // No withdrawal fee because bunny charges 0.5% already.
        IERC20(want).safeTransfer(vault, wantBal); 
    }

    function harvest() external whenNotPaused onlyEOA gasThrottle {
        IBunnyVault(bunnyVault).getReward();
        _chargeFees();
        deposit();
    }

    // Performance fees
    function _chargeFees() internal {
        uint256 toWant = IERC20(bunny).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toWant, 0, bunnyToWantRoute, address(this), now.add(600));

        uint256 toWbnb = balanceOfWant().mul(45).div(1000);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toWbnb, 0, wantToWbnbRoute, address(this), now.add(600));
    
        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));
        
        uint256 callFeeAmount = wbnbBal.mul(callFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(msg.sender, callFeeAmount);
        
        uint256 beefyFeeAmount = wbnbBal.mul(beefyFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = wbnbBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(strategist, strategistFee);
    }

    // Calculate the total underlaying {want} held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // It calculates how much {want} the contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // It calculates how much {want} the strategy has allocated in the {bunnyVault}
    function balanceOfPool() public view returns (uint256) {
        return IBunnyVault(bunnyVault).balanceOf(address(this));
    }

    // Called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IBunnyVault(bunnyVault).withdrawUnderlying(uint(-1));

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    // Pauses deposits and withdraws all funds from third party systems.
    function panic() external onlyManager {
        IBunnyVault(bunnyVault).withdrawUnderlying(uint(-1));
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
        IERC20(bunny).safeApprove(unirouter, uint(-1));
        IERC20(want).safeApprove(unirouter, uint(-1));
        IERC20(want).safeApprove(bunnyVault, uint(-1));
    }

    function _removeAllowances() internal {
        IERC20(bunny).safeApprove(unirouter, 0);
        IERC20(want).safeApprove(unirouter, 0);
        IERC20(want).safeApprove(bunnyVault, 0);
    }

    function inCaseTokensGetStuck(address _token) external onlyManager {
        require(_token != want, "!safe");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}
