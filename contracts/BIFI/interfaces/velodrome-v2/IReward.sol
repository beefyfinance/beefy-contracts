// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IReward {
    error InvalidReward();
    error NotAuthorized();
    error NotGauge();
    error NotEscrowToken();
    error NotSingleToken();
    error NotVotingEscrow();
    error NotWhitelisted();
    error ZeroAmount();

    event Deposit(address indexed from, uint256 indexed tokenId, uint256 amount);
    event Withdraw(address indexed from, uint256 indexed tokenId, uint256 amount);
    event NotifyReward(address indexed from, address indexed reward, uint256 indexed epoch, uint256 amount);
    event ClaimRewards(address indexed from, address indexed reward, uint256 amount);

    /// @notice A checkpoint for marking balance
    struct Checkpoint {
        uint256 timestamp;
        uint256 balanceOf;
    }

    /// @notice A checkpoint for marking supply
    struct SupplyCheckpoint {
        uint256 timestamp;
        uint256 supply;
    }

    /// @notice Epoch duration constant (7 days)
    function DURATION() external view returns (uint256);

    /// @notice Address of Voter.sol
    function voter() external view returns (address);

    /// @notice Address of VotingEscrow.sol
    function ve() external view returns (address);

    /// @dev Address which has permission to externally call _deposit() & _withdraw()
    function authorized() external view returns (address);

    /// @notice Total amount currently deposited via _deposit()
    function totalSupply() external view returns (uint256);

    /// @notice Current amount deposited by tokenId
    function balanceOf(uint256 tokenId) external view returns (uint256);

    /// @notice Amount of tokens to reward depositors for a given epoch
    /// @param token Address of token to reward
    /// @param epochStart Startime of rewards epoch
    /// @return Amount of token
    function tokenRewardsPerEpoch(address token, uint256 epochStart) external view returns (uint256);

    /// @notice Most recent timestamp a veNFT has claimed their rewards
    /// @param  token Address of token rewarded
    /// @param tokenId veNFT unique identifier
    /// @return Timestamp
    function lastEarn(address token, uint256 tokenId) external view returns (uint256);

    /// @notice True if a token is or has been an active reward token, else false
    function isReward(address token) external view returns (bool);

    /// @notice The number of checkpoints for each tokenId deposited
    function numCheckpoints(uint256 tokenId) external view returns (uint256);

    /// @notice The total number of checkpoints
    function supplyNumCheckpoints() external view returns (uint256);

    /// @notice Deposit an amount into the rewards contract to earn future rewards associated to a veNFT
    /// @dev Internal notation used as only callable internally by `authorized`.
    /// @param amount   Amount deposited for the veNFT
    /// @param tokenId  Unique identifier of the veNFT
    function _deposit(uint256 amount, uint256 tokenId) external;

    /// @notice Withdraw an amount from the rewards contract associated to a veNFT
    /// @dev Internal notation used as only callable internally by `authorized`.
    /// @param amount   Amount deposited for the veNFT
    /// @param tokenId  Unique identifier of the veNFT
    function _withdraw(uint256 amount, uint256 tokenId) external;

    /// @notice Claim the rewards earned by a veNFT staker
    /// @param tokenId  Unique identifier of the veNFT
    /// @param tokens   Array of tokens to claim rewards of
    function getReward(uint256 tokenId, address[] memory tokens) external;

    /// @notice Add rewards for stakers to earn
    /// @param token    Address of token to reward
    /// @param amount   Amount of token to transfer to rewards
    function notifyRewardAmount(address token, uint256 amount) external;

    /// @notice Determine the prior balance for an account as of a block number
    /// @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
    /// @param tokenId      The token of the NFT to check
    /// @param timestamp    The timestamp to get the balance at
    /// @return The balance the account had as of the given block
    function getPriorBalanceIndex(uint256 tokenId, uint256 timestamp) external view returns (uint256);

    /// @notice Determine the prior index of supply staked by of a timestamp
    /// @dev Timestamp must be <= current timestamp
    /// @param timestamp The timestamp to get the index at
    /// @return Index of supply checkpoint
    function getPriorSupplyIndex(uint256 timestamp) external view returns (uint256);

    /// @notice Get number of rewards tokens
    function rewardsListLength() external view returns (uint256);

    /// @notice Calculate how much in rewards are earned for a specific token and veNFT
    /// @param token Address of token to fetch rewards of
    /// @param tokenId Unique identifier of the veNFT
    /// @return Amount of token earned in rewards
    function earned(address token, uint256 tokenId) external view returns (uint256);
}