// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/access/Ownable.sol";
import "@openzeppelin-4/contracts/security/Pausable.sol";
import "../../interfaces/common/IUniswapRouterETH.sol";
import "./IMooVault.sol";
import "./IDCAVault.sol";

contract BeefyDCAStrategyUnirouter is Ownable, Pausable {
    using SafeERC20 for IERC20;

    // Our addresses we use in the contract. 
    IUniswapRouterETH public router;
    IMooVault public immutable mooVault;
    IERC20 public immutable want;
    IERC20 public immutable reward;
    IERC20 public immutable lpToken0;
    IERC20 public immutable lpToken1;
    IDCAVault public immutable vault; 
    address public keeper;

    // Swap Routing
    address[] public lp0ToRewardRoute;
    address[] public lp1ToRewardRoute;
    
    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    constructor(
        address _mooVault,
        address _vault, 
        address _keeper, 
        address _router, 
        address[] memory _lp0ToRewardRoute,
        address[] memory _lp1ToRewardRoute
    ) {
        vault = IDCAVault(_vault);
        mooVault = IMooVault(_mooVault);
        want = mooVault.want();
        
        keeper = _keeper;
        router = IUniswapRouterETH(_router);

        lp0ToRewardRoute = _lp0ToRewardRoute; 
        lp1ToRewardRoute = _lp1ToRewardRoute;

        lpToken0 = IERC20(_lp0ToRewardRoute[0]);
        lpToken1 = IERC20(_lp1ToRewardRoute[0]);
        require(lp0ToRewardRoute[lp0ToRewardRoute.length - 1] == address(vault.reward()), "LP0: Reward does not match");
        require(lp1ToRewardRoute[lp1ToRewardRoute.length - 1] == address(vault.reward()), "LP1: Reward does not match");
        reward = IERC20(lp0ToRewardRoute[lp0ToRewardRoute.length - 1]);

        _giveAllowances();
    }

    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    // We send the funds to work in the underlying Beefy Vault. 
     function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            mooVault.deposit(wantBal);
            emit Deposit(underlyingBalance());
        }
    }

     // Withdraw: Converts amount requested from vault to shares and withdraws from Beefy Vault, sends the want withdrew to vault. 
    function withdraw(uint256 _amount) external {
        require(msg.sender == address(vault), "!vault");

        uint256 wantBal = want.balanceOf(address(this));

        if (wantBal < _amount) {
            uint256 vaultWithdrawAmount = convertToShares(_amount - wantBal);
            mooVault.withdraw(vaultWithdrawAmount);
            wantBal = want.balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20(want).safeTransfer(msg.sender, wantBal);
        
        emit Withdraw(underlyingBalance());
    }

    function beforeDeposit() external {
        if (harvestOnDeposit) {
            _harvest();
        }
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function mooBalance() public view returns (uint256) {
        return mooVault.balanceOf(address(this));
    }

    function underlyingBalance() public view returns (uint256) {
        return convertToUnderlying(mooBalance());
    }

    // Converts mooTokens to underlying
    function convertToUnderlying(uint256 amount) public view returns (uint256) {
        uint256 underlyingAmount;
        if (mooVault.totalSupply() == 0) {
            underlyingAmount = amount;
        } else {
            underlyingAmount = amount * mooVault.balance() / mooVault.totalSupply();
        }
        return underlyingAmount;
    }

    // Converts underlying to shares
    function convertToShares(uint256 amount) public view returns (uint256) {
        uint256 sharesAmount;
        if (mooVault.totalSupply() == 0) {
            sharesAmount = amount;
        } else {
            sharesAmount = amount * mooVault.totalSupply() / mooVault.balance();
        }
        return sharesAmount;
    }

    // We take the total mooTokens held in the contract, convert to underlying and subtract the principal accounted in the vault. 
    function interestAccrued() public view returns (uint256) {
        return convertToUnderlying(mooBalance()) - vault.underlyingBalanceTotal();
    }

    // We take the calculated interest, convert back to shares so we can request withdraw.
    function interestInShares() public view returns (uint256) {
        return convertToShares(interestAccrued()); 
    }

    function harvest() external {
        _harvest();
    }

    // Harvest: If we have interest, withdraw -> removeLiquidity -> sell each side for reward -> send to vault and notify.
    function _harvest() internal {
        if (interestInShares() > 0) {
            _removeLiquidity();
            _swapAndNotify();
            lastHarvest = block.timestamp;
        }

    }

    function _swapAndNotify() internal { 
        uint256 before = reward.balanceOf(address(this));
        uint256 lp0Bal = lpToken0.balanceOf(address(this));
        uint256 lp1Bal = lpToken1.balanceOf(address(this));

        if (lp0Bal > 0) {
            router.swapExactTokensForTokens(lp0Bal, 0, lp0ToRewardRoute, address(this), block.timestamp);
        }

        if (lp1Bal > 0) {
            router.swapExactTokensForTokens(lp1Bal, 0, lp1ToRewardRoute, address(this), block.timestamp);
        }

        uint256 afterSwap = reward.balanceOf(address(this)) - before;
        if (afterSwap > 0) {
            reward.safeTransfer(address(vault), afterSwap);
            vault.notifyRewardAmount(afterSwap);
        }
    }

    function _removeLiquidity() internal {
        uint256 before = balanceOfWant();
        mooVault.withdraw(interestInShares());
        uint256 afterWithdraw = balanceOfWant() - before;
        router.removeLiquidity(address(lpToken0), address(lpToken1), afterWithdraw, 0, 0, address(this), block.timestamp);
    }
    
    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == address(vault), "!vault");

        mooVault.withdraw(mooBalance());

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(address(vault), wantBal);
    }

    function panic() public onlyManager {
        pause();
        mooVault.withdraw(mooBalance());
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        mooVault.deposit(balanceOfWant());
    }

    function setUnirouter(address _router) external onlyOwner {
        router = IUniswapRouterETH(_router);
    }

    // Set keeper to help manage the contract
    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
    }

    function _giveAllowances() internal {
        want.safeApprove(address(mooVault), type(uint).max);
        want.safeApprove(address(router), type(uint).max);

        lpToken0.safeApprove(address(router), 0);
        lpToken0.safeApprove(address(router), type(uint).max);

        lpToken1.safeApprove(address(router), 0);
        lpToken1.safeApprove(address(router), type(uint).max);
    }

    function _removeAllowances() internal {
        want.safeApprove(address(mooVault), 0);
        want.safeApprove(address(router), 0);
        lpToken0.safeApprove(address(router), 0);
        lpToken1.safeApprove(address(router), 0);
    }

     function lp0ToReward() external view returns (address[] memory) {
        return lp0ToRewardRoute;
    }

    function lp1ToReward() external view returns (address[] memory) {
        return lp1ToRewardRoute;
    }

}