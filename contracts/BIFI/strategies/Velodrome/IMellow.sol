// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMellowLpWrapper {
    struct MintParams {
        uint256 lpAmount; // Target LP tokens to mint
        uint256 amount0Max; // Max depositable amount of token0
        uint256 amount1Max; // Max depositable amount of token1
        address recipient; // Recipient of minted LP tokens
        uint256 deadline; // Expiry timestamp for minting
    }

    function core() external view returns (address);
    function positionId() external view returns (uint);
    function pool() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function totalSupply() external view returns (uint);

    function getRewards(address recipient) external returns (uint amount);
    function previewMint(uint lpAmount) external view returns (uint amount0, uint amount1);
    function mint(MintParams memory mintParams) external returns (uint actualAmount0, uint actualAmount1, uint actualLpAmount);

    function collectRewards() external;
    function timestampToRewardRatesIndex(uint timestamp) external view returns (uint);
    function rewardRates(uint index) external view returns (uint timestamp, uint value);


    function ammModule() external view returns (IAmmModule);

    function calculateAmountsForLp(
        uint256 lpAmount,
        uint256 totalSupply_,
        IAmmModule.AmmPosition memory position,
        uint160 sqrtRatioX96
    ) external pure returns (uint256 amount0, uint256 amount1);
}

interface IAmmModule {
    struct AmmPosition {
        address token0; // Address of the first token in the AMM pair
        address token1; // Address of the second token in the AMM pair
        uint24 property; // Represents a fee or tickSpacing property
        int24 tickLower; // Lower tick of the position
        int24 tickUpper; // Upper tick of the position
        uint128 liquidity; // Liquidity of the position
    }

    function getAmmPosition(uint) external view returns(AmmPosition calldata);
}

interface ICLPool {
    function gauge() external view returns (address);
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        bool unlocked
    );
}

interface IMellowCore {
    /**
     * @title ManagedPositionInfo Structure
     * @dev This structure holds information about a managed position within a liquidity management system.
     * It captures various parameters crucial for the operation, management, and strategic decision-making
     * for a specific position in Automated Market Makers (AMM) environments.
     */
    struct ManagedPositionInfo {
        /**
         * @notice Determines the portion of the Total Value Locked (TVL) in the ManagedPosition that can be used to pay for rebalancer services.
         * @dev Value is multiplied by 1e9. For instance, slippageD9 = 10'000'000 corresponds to 1% of the position.
         * This allows for fine-grained control over the economic parameters governing rebalancing actions.
         */
        uint32 slippageD9;
        /**
         * @notice A pool parameter corresponding to the ManagedPosition, usually representing tickSpacing or fee.
         * @dev This parameter helps in identifying and utilizing specific characteristics of the pool that are relevant to the management of the position.
         */
        uint24 property;
        /**
         * @notice The owner of the position, capable of performing actions such as withdraw, emptyRebalance, and parameter updates.
         * @dev Ensures that only the designated owner can modify or interact with the position, safeguarding against unauthorized access or actions.
         */
        address owner;
        /**
         * @notice The pool corresponding to the ManagedPosition.
         * @dev Identifies the specific AMM pool that this position is associated with, facilitating targeted management and operations.
         */
        address pool;
        /**
         * @notice An array of NFTs from the AMM protocol corresponding to the ManagedPosition.
         * @dev Allows for the aggregation and management of multiple AMM positions under a single managed position, enhancing the flexibility and capabilities of the system.
         */
        uint256[] ammPositionIds;
        /**
         * @notice A byte array containing custom data for the corresponding AmmModule.
         * @dev Stores information necessary for operations like staking, reward collection, etc., enabling customizable and protocol-specific interactions.
         */
        bytes callbackParams;
        /**
         * @notice A byte array containing custom data for the corresponding StrategyModule.
         * @dev Holds information about the parameters of the associated strategy, allowing for the implementation and execution of tailored strategic decisions.
         */
        bytes strategyParams;
        /**
         * @notice A byte array containing custom data for the corresponding Oracle.
         * @dev Contains parameters for price fetching and protection against MEV (Miner Extractable Value) attacks, enhancing the security and integrity of the position.
         */
        bytes securityParams;
    }

    function managedPositionAt(uint256 id) external view returns (ManagedPositionInfo memory);
}