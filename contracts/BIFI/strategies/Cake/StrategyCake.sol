// // SPDX-License-Identifier: MIT

// pragma solidity ^0.6.12;

// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
// import "@openzeppelin/contracts/math/SafeMath.sol";

// import "../../interfaces/common/IUniswapRouterETH.sol";
// import "../../interfaces/pancake/IMasterChef.sol";
// import "../../utils/GasThrottler.sol";
// import "../Common/FeeManager.sol";
// import "../Common/StratManager.sol";

// contract StrategyCake is StratManager, FeeManager, GasThrottler {
//     using SafeERC20 for IERC20;
//     using SafeMath for uint256;

//     // Tokens Used:
//     address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
//     address constant public cake = address(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
//     address constant public bifi = address(0xCa3F508B8e4Dd382eE878A314789373D80A5190A);

//     // Third Party Contracts
//     address constant public masterchef = address(0x73feaa1eE314F8c655E354234017bE2193C9E24E);

//     // Beefy Contracts
//     address constant public rewardPool  = address(0x453D4Ba9a2D594314DF88564248497F7D74d6b2C);
//     address constant public treasury = address(0x4A32De8c248533C28904b24B4cFCFE18E9F2ad01);

//     // Routes
//     address[] public cakeToWbnbRoute = [cake, wbnb];
//     address[] public wbnbToBifiRoute = [wbnb, bifi];

//     /**
//      * @param _keeper Address of extra maintainer
//      * @param _strategist Address where stategist fees go.
//      * @param _unirouter Address of router for swaps
//      * @param _vault Address of parent vault
//      */
//     constructor(
//         address _keeper, 
//         address _strategist,
//         address _unirouter,
//         address _vault 
//     ) StratManager(_keeper, _strategist, _unirouter, _vault) public {
//         vault = _vault;

//         _giveAllowances();
//     }

//     function deposit() public whenNotPaused {
//         _deposit();
//     }

//     function _deposit() internal {
//         uint256 cakeBal = balanceOfCake();

//         if (cakeBal > 0) {
//             IMasterChef(masterchef).enterStaking(cakeBal);
//         }
//     }

//     function withdraw(uint256 _amount) external {
//         require(msg.sender == vault, "!vault");

//         uint256 cakeBal = balanceOfCake();

//         if (cakeBal < _amount) {
//             IMasterChef(masterchef).leaveStaking(_amount.sub(cakeBal));
//             cakeBal = balanceOfCake();
//         }

//         if (cakeBal > _amount) {
//             cakeBal = _amount;    
//         }
        
//         if (tx.origin == owner() || paused()) {
//             IERC20(cake).safeTransfer(vault, cakeBal); 
//         } else {
//             uint256 withdrawalFee = cakeBal.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
//             IERC20(cake).safeTransfer(vault, cakeBal.sub(withdrawalFee)); 
//         }
//     }

//     function harvest() external whenNotPaused gasThrottle {
//         IMasterChef(masterchef).leaveStaking(0);
//         _chargeFees();
//         deposit();
//     }

//     // Performance fees
//     function _chargeFees() internal {
//         uint256 toWbnb = balanceOfCake().mul(45).div(1000);
//         IUniswapRouterETH(unirouter).swapExactTokensForTokens(toWbnb, 0, cakeToWbnbRoute, address(this), now.add(600));
    
//         uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));
        
//         uint256 callFeeAmount = wbnbBal.mul(callFee).div(MAX_FEE);
//         IERC20(wbnb).safeTransfer(tx.origin, callFeeAmount);
        
//         uint256 treasuryHalf = wbnbBal.mul(TREASURY_FEE).div(MAX_FEE).div(2);
//         IERC20(wbnb).safeTransfer(treasury, treasuryHalf);
//         IUniswapRouterETH(unirouter).swapExactTokensForTokens(treasuryHalf, 0, wbnbToBifiRoute, treasury, now.add(600));
        
//         uint256 rewardsFeeAmount = wbnbBal.mul(rewardsFee).div(MAX_FEE);
//         IERC20(wbnb).safeTransfer(rewardPool, rewardsFeeAmount);

//         uint256 strategistFee = wbnbBal.mul(STRATEGIST_FEE).div(MAX_FEE);
//         IERC20(wbnb).safeTransfer(strategist, strategistFee);
//     }

//     // Calculate the total underlaying {cake} held by the strat.
//     function balanceOf() public view returns (uint256) {
//         return balanceOfCake().add(balanceOfPool());
//     }

//     // It calculates how much {cake} the contract holds.
//     function balanceOfCake() public view returns (uint256) {
//         return IERC20(cake).balanceOf(address(this));
//     }

//     // It calculates how much {cake} the strategy has allocated in the farm.
//     function balanceOfPool() public view returns (uint256) {
//         (uint256 _amount, ) = IMasterChef(masterchef).userInfo(0, address(this));
//         return _amount;
//     }

//     // Called as part of strat migration. Sends all the available funds back to the vault.
//     function retireStrat() external {
//         require(msg.sender == vault, "!vault");

//         IMasterChef(masterchef).emergencyWithdraw(0);

//         uint256 cakeBal = balanceOfCake();
//         IERC20(cake).transfer(vault, cakeBal);
//     }

//     // Pauses deposits and withdraws all funds from third party systems.
//     function panic() external onlyOwner {
//         pause();
//         IMasterChef(masterchef).emergencyWithdraw(0);
//     }

//     function pause() public onlyOwner {
//         _pause();
//         _removeAllowances();
//     }

//     function unpause() external onlyOwner {
//         _unpause();
//         _giveAllowances();
//         deposit();
//     }

//     function _giveAllowances() internal {
//         IERC20(cake).safeApprove(unirouter, uint(-1));
//         IERC20(wbnb).safeApprove(unirouter, uint(-1));
//         IERC20(cake).safeApprove(masterchef, uint(-1));
//     }

//     function _removeAllowances() internal {
//         IERC20(cake).safeApprove(unirouter, 0);
//         IERC20(wbnb).safeApprove(unirouter, 0);
//         IERC20(cake).safeApprove(masterchef, 0);
//     }

//     function inCaseTokensGetStuck(address _token) external onlyManager {
//         require(_token != cake, "!safe");

//         uint256 amount = IERC20(_token).balanceOf(address(this));
//         IERC20(_token).safeTransfer(msg.sender, amount);
//     }
// }
