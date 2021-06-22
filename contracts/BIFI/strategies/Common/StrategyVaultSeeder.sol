// // SPDX-License-Identifier: MIT

// pragma solidity ^0.6.12;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
// import "@openzeppelin/contracts/math/SafeMath.sol";

// import "../../interfaces/common/IUniswapRouterETH.sol";
// import "../../interfaces/common/IUniswapV2Pair.sol";
// import "../../interfaces/beefy/ISeededVault.sol";
// import "./StratManager.sol";

// contract StrategyCake is Ownable {
//     using SafeERC20 for IERC20;
//     using SafeMath for uint256;

//     // Tokens used
//     address public lpPair;
//     address public lpToken0;
//     address public lpToken1;
//     address public newLpPair;

//     // Third Party Contracts
//     address constant public oldUnirouter  = address(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
//     address constant public newUnirouter  = address(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);

//     // Beefy Contracts
//     address public immutable vault;
//     address public immutable seededVault;

//     /**
//      * @param _vault Address of parent vault
//      */
//     constructor(address _lpPair, address _newLpPair, address _seededVault, address _vault) public {
//         lpPair = _lpPair;
//         lpToken0 = IUniswapV2Pair(lpPair).token0();
//         lpToken1 = IUniswapV2Pair(lpPair).token1();
//         newLpPair = _newLpPair;
//         seededVault = _seededVault;
//         vault = _vault;

//         IERC20(lpPair).safeApprove(oldUnirouter, uint(-1));
//         IERC20(lpToken0).safeApprove(newUnirouter, uint(-1));
//         IERC20(lpToken1).safeApprove(newUnirouter, uint(-1));
//     }

//     // required to accept funds from old strat
//     function deposit() external {}

//     function seed() external onlyOwner {
//         // 1. Remove liquidity from old pair.
//         uint lpPairBal = IERC20(lpPair).balanceOf(address(this));
//         IUniswapRouterETH(oldUnirouter).removeLiquidity(lpToken0, lpToken1, lpPairBal, 1, 1, address(this), now);
        
//         // 2. Add liquidity to new pair.
//         uint lp0Bal = IERC20(lpToken0).balanceOf(address(this));
//         uint lp1Bal = IERC20(lpToken1).balanceOf(address(this));
//         IUniswapRouterETH(newUnirouter).addLiquidity(lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), now);

//         // 3. Send new lp funds to new vault.
//         address newStrat = ISeededVault(seededVault).strategy();
//         uint newLpPairBal = IERC20(newLpPair).balanceOf(address(this));
//         IERC20(newLpPair).safeTransfer(newStrat, newLpPairBal);

//         // 4. Send also the dust from both tokens just in case.
//         lp0Bal = IERC20(lpToken0).balanceOf(address(this));
//         lp1Bal = IERC20(lpToken1).balanceOf(address(this));
//         IERC20(lpToken0).safeTransfer(newStrat, lp0Bal);
//         IERC20(lpToken1).safeTransfer(newStrat, lp1Bal);

//         // 4. Call seed.
//         ISeededVault(seededVault).seed();
//     }
// }
