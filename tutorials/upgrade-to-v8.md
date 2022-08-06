# Upgrade to Solidity v0.8

This tutorial will take you through the process of:

1. upgrading existing strategies to Solidity version 0.8 from 0.6
2. use the new fee config to fetch fees dynamically

For reference please see the contract [StrategyCommonChefLP] which already has all the proposed changes applied.

## Important changes

There are a few version-breaking changes that need to be taken into account when upgrading.

1. SafeMath is implemented in `uint256` automatically so all references have to be removed 
2. overflows always throw errors so all `uint256(-1)` will have to changed to `type(uint256).max`
3. `pragma experimental ABIEncoderV2` is enabled for every file by default
4. the reference to the current timestamp `now` has been depreciated in favour of `block.timestamp`
5. imports such as OpenZeppelin have to updated to the version that uses 0.8

In addition to version changes all strategies will now use the BeefyFeeConfigurator contract to fetch a fee struct. This will replace the hardcoded 4.5% fees and centralise the control of the fee splits.

## Step-by-step

1. Change the Solidity version of the strategy to 0.8 from 0.6
```
pragma solidity ^0.8.0
```
2. Replace exisiting OpenZeppelin imports with the 0.8 versions, removing SafeMath entirely
```
import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
```
3. Upgrade Solidity version on interfaces to support all versions from 0.6 to 0.8
```
pragma solidity >=0.6.0 <0.9.0;
```
4. Replace StratManager, FeeManager and GasThrottler imports with StratFeeManager and GasFeeThrottler
```
import "../Common/StratFeeManager.sol";
import "../../utils/GasFeeThrottler.sol
```
5. Remove the line `using SafeMath for uint256;`
6. Replace these lines in the constructor arguments:
```
address _vault,
address _unirouter,
address _keeper,
address _strategist,
address _beefyFeeRecipient,
```
with the single line `CommonAddresses memory _commonAddresses,` which is a struct containing:
```
struct CommonAddresses {
   address vault;
   address unirouter;
   address keeper;
   address strategist;
   address beefyFeeRecipient;
   address beefyFeeConfig;
}
```
7. Similarly replace the StratManager constructor with `StratFeeManager(_commonAddresses)` and remove the `public` identifier
8. Find and replace every instance of `.add`, `.sub`, `.mul` and `.div` with the actual operator, i.e. replace `.div` with `/`
9. Find and replace every instance of `now` with `block.timestamp`
10. Find and replace every instance of `uint256(-1)` (or any use of overflow) with `type(uint256).max`
11. Find and replace every instance of `MAX_FEE` with `DIVISOR`
12. Add the following line at the start of `chargeFees` and `callReward` to fetch the fee struct from the BeefyFeeConfigurator contract:
```
IFeeConfig.FeeCategory memory fees = getFees();
```
The struct has the following properties:
```
struct FeeCategory {
    uint256 total;      // total fee charged on each harvest
    uint256 beefy;      // split of total fee going to beefy fee batcher
    uint256 call;       // split of total fee going to harvest caller
    uint256 strategist;     // split of total fee going to developer of the strategy
    string label;       // description of the type of fee category
    bool active;        // on/off switch for fee category
}
```
13. Replace `callFee` with `fees.call`, `beefyFee` with `fees.beefy`, `STRATEGIST_FEE` with `fees.strategist`
14. Replace the total fee charged (previously 4.5%) with the dynamic fee `fees.total` in both `chargeFees` and `callReward`
```
uint256 toNative = IERC20(output).balanceOf(address(this)) * fees.total / DIVISOR;
```
```return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;```

The default fee will automatically be charged, but in the future you may be required to change it to a different fee category. After deployment you will be able to use `setStratFeeCategory(uint256 feeCategory)` to set to a different existing category. Setting the id to a non-existent category will return default fees.

[StrategyCommonChefLP]: ../contracts/BIFI/strategies/Common/StrategyCommonChefLP.sol
