// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IComptroller.sol";
import "./StrategyCompoundV2.sol";


//Lending Strategy 
contract StrategyCompoundV2Uniswap is StrategyCompoundV2 {
    using SafeERC20 for IERC20;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToWantRoute;


    constructor(
        uint256 _borrowRate,
        uint256 _borrowRateMax,
        uint256 _borrowDepth,
        uint256 _minLeverage,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToWantRoute,
        address[] memory _markets,
        address _comptroller,
        CommonAddresses memory _commonAddresses
    ) StrategyCompoundV2(_borrowRate, _borrowRateMax, _borrowDepth, _minLeverage, _markets, _comptroller, _commonAddresses) {
        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        require(_outputToWantRoute[0] == output, "outputToWantRoute[0] != output");
        require(_outputToWantRoute[_outputToWantRoute.length - 1] == want, "outputToNativeRoute[last] != want");
        outputToWantRoute = _outputToWantRoute;

        _giveAllowances();
        IComptroller(comptroller).enterMarkets(markets);
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal override {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 toNative = IERC20(output).balanceOf(address(this)) * fees.total / DIVISOR;
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(
            toNative, 0, outputToNativeRoute, address(this), block.timestamp
        );

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // swap rewards to {want}
    function swapRewards() internal override{
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputBal, 0, outputToWantRoute, address(this), block.timestamp);
    }

    // native reward amount for calling harvest
    function callReward() public override returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            uint256[] memory amountOut = IUniswapRouterETH(unirouter).getAmountsOut(outputBal, outputToNativeRoute);
            nativeOut = amountOut[amountOut.length -1];
        }

        return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;
    }

     function outputToNative() external view override returns(address[] memory) {
        return outputToNativeRoute;
    }

    function outputToWant() external view override returns(address[] memory) {
        return outputToWantRoute;
    }
}