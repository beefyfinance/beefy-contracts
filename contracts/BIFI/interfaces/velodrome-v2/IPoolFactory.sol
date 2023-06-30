// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPoolFactory {
    event SetFeeManager(address feeManager);
    event SetPauser(address pauser);
    event SetPauseState(bool state);
    event SetVoter(address voter);
    event PoolCreated(address indexed token0, address indexed token1, bool indexed stable, address pool, uint256);
    event SetCustomFee(address indexed pool, uint256 fee);

    error FeeInvalid();
    error FeeTooHigh();
    error InvalidPool();
    error NotFeeManager();
    error NotPauser();
    error NotSinkConverter();
    error NotVoter();
    error PoolAlreadyExists();
    error SameAddress();
    error ZeroFee();
    error ZeroAddress();

    /// @notice returns the number of pools created from this factory
    function allPoolsLength() external view returns (uint256);

    /// @notice Is a valid pool created by this factory.
    /// @param .
    function isPool(address pool) external view returns (bool);

    /// @notice Support for Velodrome v1 which wraps around isPool(pool);
    /// @param .
    function isPair(address pool) external view returns (bool);

    /// @notice Return address of pool created by this factory
    /// @param tokenA .
    /// @param tokenB .
    /// @param stable True if stable, false if volatile
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);

    /// @notice Support for v3-style pools which wraps around getPool(tokenA,tokenB,stable)
    /// @dev fee is converted to stable boolean.
    /// @param tokenA .
    /// @param tokenB .
    /// @param fee  1 if stable, 0 if volatile, else returns address(0)
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);

    /// @notice Support for Velodrome v1 pools as a "pool" was previously referenced as "pair"
    /// @notice Wraps around getPool(tokenA,tokenB,stable)
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address);

    /// @dev Only called once to set to Voter.sol - Voter does not have a function
    ///      to call this contract method, so once set it's immutable.
    ///      This also follows convention of setVoterAndDistributor() in VotingEscrow.sol
    /// @param _voter .
    function setVoter(address _voter) external;

    function setSinkConverter(address _sinkConvert, address _velo, address _veloV2) external;

    function setPauser(address _pauser) external;

    function setPauseState(bool _state) external;

    function setFeeManager(address _feeManager) external;

    /// @notice Set default fee for stable and volatile pools.
    /// @dev Throws if higher than maximum fee.
    ///      Throws if fee is zero.
    /// @param _stable Stable or volatile pool.
    /// @param _fee .
    function setFee(bool _stable, uint256 _fee) external;

    /// @notice Set overriding fee for a pool from the default
    /// @dev A custom fee of zero means the default fee will be used.
    function setCustomFee(address _pool, uint256 _fee) external;

    /// @notice Returns fee for a pool, as custom fees are possible.
    function getFee(address _pool, bool _stable) external view returns (uint256);

    /// @notice Create a pool given two tokens and if they're stable/volatile
    /// @dev token order does not matter
    /// @param tokenA .
    /// @param tokenB .
    /// @param stable .
    function createPool(address tokenA, address tokenB, bool stable) external returns (address pool);

    /// @notice Support for v3-style pools which wraps around createPool(tokena,tokenB,stable)
    /// @dev fee is converted to stable boolean
    /// @dev token order does not matter
    /// @param tokenA .
    /// @param tokenB .
    /// @param fee 1 if stable, 0 if volatile, else revert
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);

    /// @notice Support for Velodrome v1 which wraps around createPool(tokenA,tokenB,stable)
    function createPair(address tokenA, address tokenB, bool stable) external returns (address pool);

    function isPaused() external view returns (bool);

    function velo() external view returns (address);

    function veloV2() external view returns (address);

    function voter() external view returns (address);

    function sinkConverter() external view returns (address);

    function implementation() external view returns (address);
}
