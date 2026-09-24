// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Pool state that can change
/// @dev Important security note: when using this data by external contracts, it is necessary to take into account the possibility
/// of manipulation (including read-only reentrancy).
/// This interface is based on the UniswapV3 interface, credit to Uniswap Labs under GPL-2.0-or-later license:
/// https://github.com/Uniswap/v3-core/tree/main/contracts/interfaces
interface IKimPool {
  /// @notice Safely get most important state values of Algebra Integral AMM
  /// @dev Several values exposed as a single method to save gas when accessed externally.
  /// **Important security note: this method checks reentrancy lock and should be preferred in most cases**.
  /// @return sqrtPrice The current price of the pool as a sqrt(dToken1/dToken0) Q64.96 value
  /// @return tick The current global tick of the pool. May not always be equal to SqrtTickMath.getTickAtSqrtRatio(price) if the price is on a tick boundary
  /// @return lastFee The current (last known) pool fee value in hundredths of a bip, i.e. 1e-6 (so '100' is '0.01%'). May be obsolete if using dynamic fee plugin
  /// @return pluginConfig The current plugin config as bitmap. Each bit is responsible for enabling/disabling the hooks, the last bit turns on/off dynamic fees logic
  /// @return activeLiquidity  The currently in-range liquidity available to the pool
  /// @return nextTick The next initialized tick after current global tick
  /// @return previousTick The previous initialized tick before (or at) current global tick
  function safelyGetStateOfAMM()
    external
    view
    returns (uint160 sqrtPrice, int24 tick, uint16 lastFee, uint8 pluginConfig, uint128 activeLiquidity, int24 nextTick, int24 previousTick);

  /// @notice Allows to easily get current reentrancy lock status
  /// @dev can be used to prevent read-only reentrancy.
  /// This method just returns `globalState.unlocked` value
  /// @return unlocked Reentrancy lock flag, true if the pool currently is unlocked, otherwise - false
  function isUnlocked() external view returns (bool unlocked);

  // ! IMPORTANT security note: the pool state can be manipulated.
  // ! The following methods do not check reentrancy lock themselves.

  /// @notice The globalState structure in the pool stores many values but requires only one slot
  /// and is exposed as a single method to save gas when accessed externally.
  /// @dev **important security note: caller should check `unlocked` flag to prevent read-only reentrancy**
  /// @return price The current price of the pool as a sqrt(dToken1/dToken0) Q64.96 value
  /// @return tick The current tick of the pool, i.e. according to the last tick transition that was run
  /// This value may not always be equal to SqrtTickMath.getTickAtSqrtRatio(price) if the price is on a tick boundary
  /// @return lastFee The current (last known) pool fee value in hundredths of a bip, i.e. 1e-6 (so '100' is '0.01%'). May be obsolete if using dynamic fee plugin
  /// @return pluginConfig The current plugin config as bitmap. Each bit is responsible for enabling/disabling the hooks, the last bit turns on/off dynamic fees logic
  /// @return communityFee The community fee represented as a percent of all collected fee in thousandths, i.e. 1e-3 (so 100 is 10%)
  /// @return unlocked Reentrancy lock flag, true if the pool currently is unlocked, otherwise - false
  function globalState() external view returns (uint160 price, int24 tick, uint16 lastFee, uint8 pluginConfig, uint16 communityFee, bool unlocked);

  /// @notice Look up information about a specific tick in the pool
  /// @dev **important security note: caller should check reentrancy lock to prevent read-only reentrancy**
  /// @param tick The tick to look up
  /// @return liquidityTotal The total amount of position liquidity that uses the pool either as tick lower or tick upper
  /// @return liquidityDelta How much liquidity changes when the pool price crosses the tick
  /// @return prevTick The previous tick in tick list
  /// @return nextTick The next tick in tick list
  /// @return outerFeeGrowth0Token The fee growth on the other side of the tick from the current tick in token0
  /// @return outerFeeGrowth1Token The fee growth on the other side of the tick from the current tick in token1
  /// In addition, these values are only relative and must be used only in comparison to previous snapshots for
  /// a specific position.
  function ticks(
    int24 tick
  )
    external
    view
    returns (
      uint256 liquidityTotal,
      int128 liquidityDelta,
      int24 prevTick,
      int24 nextTick,
      uint256 outerFeeGrowth0Token,
      uint256 outerFeeGrowth1Token
    );

  /// @notice The timestamp of the last sending of tokens to community vault
  /// @return The timestamp truncated to 32 bits
  function communityFeeLastTimestamp() external view returns (uint32);

  /// @notice The amounts of token0 and token1 that will be sent to the vault
  /// @dev Will be sent COMMUNITY_FEE_TRANSFER_FREQUENCY after communityFeeLastTimestamp
  /// @return communityFeePending0 The amount of token0 that will be sent to the vault
  /// @return communityFeePending1 The amount of token1 that will be sent to the vault
  function getCommunityFeePending() external view returns (uint128 communityFeePending0, uint128 communityFeePending1);

  /// @notice Returns the address of currently used plugin
  /// @dev The plugin is subject to change
  /// @return pluginAddress The address of currently used plugin
  function plugin() external view returns (address pluginAddress);

  /// @notice The contract to which community fees are transferred
  /// @return communityVaultAddress The communityVault address
  function communityVault() external view returns (address communityVaultAddress);

  /// @notice Returns 256 packed tick initialized boolean values. See TickTree for more information
  /// @param wordPosition Index of 256-bits word with ticks
  /// @return The 256-bits word with packed ticks info
  function tickTable(int16 wordPosition) external view returns (uint256);

  /// @notice The fee growth as a Q128.128 fees of token0 collected per unit of liquidity for the entire life of the pool
  /// @dev This value can overflow the uint256
  /// @return The fee growth accumulator for token0
  function totalFeeGrowth0Token() external view returns (uint256);

  /// @notice The fee growth as a Q128.128 fees of token1 collected per unit of liquidity for the entire life of the pool
  /// @dev This value can overflow the uint256
  /// @return The fee growth accumulator for token1
  function totalFeeGrowth1Token() external view returns (uint256);

  /// @notice The current pool fee value
  /// @dev In case dynamic fee is enabled in the pool, this method will call the plugin to get the current fee.
  /// If the plugin implements complex fee logic, this method may return an incorrect value or revert.
  /// In this case, see the plugin implementation and related documentation.
  /// @dev **important security note: caller should check reentrancy lock to prevent read-only reentrancy**
  /// @return currentFee The current pool fee value in hundredths of a bip, i.e. 1e-6
  function fee() external view returns (uint16 currentFee);

  /// @notice The tracked token0 and token1 reserves of pool
  /// @dev If at any time the real balance is larger, the excess will be transferred to liquidity providers as additional fee.
  /// If the balance exceeds uint128, the excess will be sent to the communityVault.
  /// @return reserve0 The last known reserve of token0
  /// @return reserve1 The last known reserve of token1
  function getReserves() external view returns (uint128 reserve0, uint128 reserve1);

  /// @notice Returns the information about a position by the position's key
  /// @dev **important security note: caller should check reentrancy lock to prevent read-only reentrancy**
  /// @param key The position's key is a packed concatenation of the owner address, bottomTick and topTick indexes
  /// @return liquidity The amount of liquidity in the position
  /// @return innerFeeGrowth0Token Fee growth of token0 inside the tick range as of the last mint/burn/poke
  /// @return innerFeeGrowth1Token Fee growth of token1 inside the tick range as of the last mint/burn/poke
  /// @return fees0 The computed amount of token0 owed to the position as of the last mint/burn/poke
  /// @return fees1 The computed amount of token1 owed to the position as of the last mint/burn/poke
  function positions(
    bytes32 key
  ) external view returns (uint256 liquidity, uint256 innerFeeGrowth0Token, uint256 innerFeeGrowth1Token, uint128 fees0, uint128 fees1);

  /// @notice The currently in range liquidity available to the pool
  /// @dev This value has no relationship to the total liquidity across all ticks.
  /// Returned value cannot exceed type(uint128).max
  /// @dev **important security note: caller should check reentrancy lock to prevent read-only reentrancy**
  /// @return The current in range liquidity
  function liquidity() external view returns (uint128);

  /// @notice The current tick spacing
  /// @dev Ticks can only be initialized by new mints at multiples of this value
  /// e.g.: a tickSpacing of 60 means ticks can be initialized every 60th tick, i.e., ..., -120, -60, 0, 60, 120, ...
  /// However, tickspacing can be changed after the ticks have been initialized.
  /// This value is an int24 to avoid casting even though it is always positive.
  /// @return The current tick spacing
  function tickSpacing() external view returns (int24);

  /// @notice The previous initialized tick before (or at) current global tick
  /// @dev **important security note: caller should check reentrancy lock to prevent read-only reentrancy**
  /// @return The previous initialized tick
  function prevTickGlobal() external view returns (int24);

  /// @notice The next initialized tick after current global tick
  /// @dev **important security note: caller should check reentrancy lock to prevent read-only reentrancy**
  /// @return The next initialized tick
  function nextTickGlobal() external view returns (int24);

  /// @notice The root of tick search tree
  /// @dev Each bit corresponds to one node in the second layer of tick tree: '1' if node has at least one active bit.
  /// **important security note: caller should check reentrancy lock to prevent read-only reentrancy**
  /// @return The root of tick search tree as bitmap
  function tickTreeRoot() external view returns (uint32);

  /// @notice The second layer of tick search tree
  /// @dev Each bit in node corresponds to one node in the leafs layer (`tickTable`) of tick tree: '1' if leaf has at least one active bit.
  /// **important security note: caller should check reentrancy lock to prevent read-only reentrancy**
  /// @return The node of tick search tree second layer
  function tickTreeSecondLayer(int16) external view returns (uint256);

  function token0() external view returns (address);
  function token1() external view returns (address);

  /// @notice Adds liquidity for the given recipient/bottomTick/topTick position
  /// @dev The caller of this method receives a callback in the form of IAlgebraMintCallback#algebraMintCallback
  /// in which they must pay any token0 or token1 owed for the liquidity. The amount of token0/token1 due depends
  /// on bottomTick, topTick, the amount of liquidity, and the current price.
  /// @param leftoversRecipient The address which will receive potential surplus of paid tokens
  /// @param recipient The address for which the liquidity will be created
  /// @param bottomTick The lower tick of the position in which to add liquidity
  /// @param topTick The upper tick of the position in which to add liquidity
  /// @param liquidityDesired The desired amount of liquidity to mint
  /// @param data Any data that should be passed through to the callback
  /// @return amount0 The amount of token0 that was paid to mint the given amount of liquidity. Matches the value in the callback
  /// @return amount1 The amount of token1 that was paid to mint the given amount of liquidity. Matches the value in the callback
  /// @return liquidityActual The actual minted amount of liquidity
  function mint(
    address leftoversRecipient,
    address recipient,
    int24 bottomTick,
    int24 topTick,
    uint128 liquidityDesired,
    bytes calldata data
  ) external returns (uint256 amount0, uint256 amount1, uint128 liquidityActual);

  /// @notice Collects tokens owed to a position
  /// @dev Does not recompute fees earned, which must be done either via mint or burn of any amount of liquidity.
  /// Collect must be called by the position owner. To withdraw only token0 or only token1, amount0Requested or
  /// amount1Requested may be set to zero. To withdraw all tokens owed, caller may pass any value greater than the
  /// actual tokens owed, e.g. type(uint128).max. Tokens owed may be from accumulated swap fees or burned liquidity.
  /// @param recipient The address which should receive the fees collected
  /// @param bottomTick The lower tick of the position for which to collect fees
  /// @param topTick The upper tick of the position for which to collect fees
  /// @param amount0Requested How much token0 should be withdrawn from the fees owed
  /// @param amount1Requested How much token1 should be withdrawn from the fees owed
  /// @return amount0 The amount of fees collected in token0
  /// @return amount1 The amount of fees collected in token1
  function collect(
    address recipient,
    int24 bottomTick,
    int24 topTick,
    uint128 amount0Requested,
    uint128 amount1Requested
  ) external returns (uint128 amount0, uint128 amount1);

  /// @notice Burn liquidity from the sender and account tokens owed for the liquidity to the position
  /// @dev Can be used to trigger a recalculation of fees owed to a position by calling with an amount of 0
  /// @dev Fees must be collected separately via a call to #collect
  /// @param bottomTick The lower tick of the position for which to burn liquidity
  /// @param topTick The upper tick of the position for which to burn liquidity
  /// @param amount How much liquidity to burn
  /// @param data Any data that should be passed through to the plugin
  /// @return amount0 The amount of token0 sent to the recipient
  /// @return amount1 The amount of token1 sent to the recipient
  function burn(int24 bottomTick, int24 topTick, uint128 amount, bytes calldata data) external returns (uint256 amount0, uint256 amount1);
}
