// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

interface IAeroRouter {
    enum SpendMode {
        Amount,
        Pips
    }

    struct BalanceSpend {
        SpendMode mode;
        uint256 value;
    }

    struct AddLiquidityParams {
        address factory;
        address tokenA;
        address tokenB;
        bool createPool;
        BalanceSpend spendA;
        BalanceSpend spendB;
        bool payerAIsUser;
        bool payerBIsUser;
        uint256 amountAMin;
        uint256 amountBMin;
        address recipient;
        uint256 liquidityMin;
    }

    function EMISSION_TOKEN() external view returns (address);
    function FACTORY_REGISTRY() external view returns (address);
    function LEAF_VOTER() external view returns (address);
    function WETH() external view returns (address);
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

interface IAeroPair {
    function POOL_TYPE() external view returns (bytes32);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast);
}

interface IAeroGauge {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function emergencyWithdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function claimEmissions(address account, address recipient) external;
    function depositBlock(address account) external view returns (uint256);
    function stakingToken() external view returns (address);
    function voter() external view returns (address);
    function gaugeFactory() external view returns (address);
    function isPool() external view returns (bool);
}

interface IAeroFactoryRegistry {
    function targetToGauge(address target) external view returns (address);
}

interface IAeroPoolFactory {
    function getPool(address token0, address token1) external view returns (address);
}

interface IAeroGaugeFactory {
    struct PenaltyConfig {
        uint256 minStakeBlocks;
        uint256 penaltyRate;
    }

    function effectivePenaltyConfig(address gauge) external view returns (PenaltyConfig memory);
    function emergencyWithdrawEnabled() external view returns (bool);
}
