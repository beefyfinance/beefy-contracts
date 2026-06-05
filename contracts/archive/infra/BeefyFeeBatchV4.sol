// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { SafeERC20Upgradeable, IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { IBeefySwapper } from "../interfaces/beefy/IBeefySwapper.sol";
import { IBeefyRewardPool } from "../interfaces/beefy/IBeefyRewardPool.sol";
import { IWrappedNative } from "../interfaces/common/IWrappedNative.sol";

/// @title Beefy fee batch
/// @author kexley, Beefy
/// @notice All Beefy fees will flow through to the treasury and the reward pool
/// @dev Wrapped ETH will build up on this contract and will be swapped via the Beefy Swapper to
/// the pre-specified tokens and distributed to the treasury and reward pool
contract BeefyFeeBatchV4 is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev Bundled token information
    /// @param tokens Token addresses to swap to
    /// @param index Location of a token in the tokens array
    /// @param allocPoint Allocation points for this token
    /// @param totalAllocPoint Total amount of allocation points assigned to tokens in the array
    struct TokenInfo {
        address[] tokens;
        mapping(address => uint256) index;
        mapping(address => uint256) allocPoint;
        uint256 totalAllocPoint;
    }

    /// @notice Native token (WETH)
    IERC20Upgradeable public native;

    /// @notice Treasury address
    address public treasury;

    /// @notice Reward pool address
    address public rewardPool;

    /// @notice Swapper address to swap all tokens at
    address public swapper;

    /// @notice Vault harvester
    address public harvester;

    /// @notice Treasury fee of the total native received on the contract (1 = 0.1%)
    uint256 public treasuryFee;

    /// @notice Denominator constant
    uint256 constant public DIVISOR = 1000;

    /// @notice Duration of reward distributions
    uint256 public duration;

    /// @notice Minimum operating gas level on the harvester
    uint256 public harvesterMax;

    /// @notice Whether to send gas to the harvester
    bool public sendHarvesterGas;

    /// @notice Tokens to be sent to the treasury
    TokenInfo public treasuryTokens;

    /// @notice Tokens to be sent to the reward pool
    TokenInfo public rewardTokens;

    /// @notice Fees have been harvested
    /// @param totalHarvested Total fee amount that has been processed
    /// @param timestamp Timestamp of the harvest
    event Harvest(uint256 totalHarvested, uint256 timestamp);
    /// @notice Harvester has been sent gas
    /// @param gas Amount of gas that has been sent
    event SendHarvesterGas(uint256 gas);
    /// @notice Treasury fee that has been sent
    /// @param token Token that has been sent
    /// @param amount Amount of the token sent
    event DistributeTreasuryFee(address indexed token, uint256 amount);
    /// @notice Reward pool has been notified
    /// @param token Token used as a reward
    /// @param amount Amount of the token used
    /// @param duration Duration of the distribution
    event NotifyRewardPool(address indexed token, uint256 amount, uint256 duration);
    /// @notice Reward pool set
    /// @param rewardPool New reward pool address
    event SetRewardPool(address rewardPool);
    /// @notice Treasury set
    /// @param treasury New treasury address
    event SetTreasury(address treasury);
    /// @notice Whether to send gas to harvester has been set
    /// @param send Whether to send gas to harvester
    event SetSendHarvesterGas(bool send);
    /// @notice Harvester set
    /// @param harvester New harvester address
    /// @param harvesterMax Minimum operating gas level for the harvester
    event SetHarvester(address harvester, uint256 harvesterMax);
    /// @notice Swapper set
    /// @param swapper New swapper address
    event SetSwapper(address swapper);
    /// @notice Treasury fee set
    /// @param fee New fee split for the treasury
    event SetTreasuryFee(uint256 fee);
    /// @notice Reward pool duration set
    /// @param duration New duration of the reward distribution
    event SetDuration(uint256 duration);
    /// @notice Set the whitelist status of a manager for the reward pool
    /// @param manager Address of the manager
    /// @param whitelisted Status of the manager on the whitelist
    event SetWhitelistOfRewardPool(address manager, bool whitelisted);
    /// @notice Remove a reward from the reward pool distribution
    /// @param reward Address of the reward to remove
    /// @param recipient Address to send the reward to
    event RemoveRewardFromRewardPool(address reward, address recipient);
    /// @notice Rescue an unsupported token from the reward pool
    /// @param token Address of the token to remove
    /// @param recipient Address to send the token to
    event RescueTokensFromRewardPool(address token, address recipient);
    /// @notice Transfer ownership of the reward pool to a new owner
    /// @param owner New owner of the reward pool
    event TransferOwnershipOfRewardPool(address owner);
    /// @notice Rescue an unsupported token
    /// @param token Address of the token
    /// @param recipient Address to send the token to
    event RescueTokens(address token, address recipient);

    /// @notice Initialize the contract, callable only once
    /// @param _native WETH address
    /// @param _rewardPool Reward pool address
    /// @param _treasury Treasury address
    /// @param _swapper Swapper address
    /// @param _treasuryFee Treasury fee split
    function initialize(
        address _native,
        address _rewardPool,
        address _treasury,
        address _swapper,
        uint256 _treasuryFee 
    ) external initializer {
        __Ownable_init();

        native = IERC20Upgradeable(_native);
        treasury = _treasury;
        rewardPool = _rewardPool;
        treasuryFee = _treasuryFee;
        swapper = _swapper;
        native.forceApprove(swapper, type(uint).max);
        duration = 7 days;
    }

    /// @notice Distribute the fees to the harvester, treasury and reward pool
    function harvest() external {
        uint256 totalFees = native.balanceOf(address(this));

        if (sendHarvesterGas) _sendHarvesterGas();
        _distributeTreasuryFee();
        _notifyRewardPool();

        emit Harvest(totalFees - native.balanceOf(address(this)), block.timestamp);
    }

    /// @dev Unwrap the required amount of native and send to the harvester
    function _sendHarvesterGas() private {
        uint256 nativeBal = native.balanceOf(address(this));

        uint256 harvesterBal = harvester.balance + native.balanceOf(harvester);
        if (harvesterBal < harvesterMax) {
            uint256 gas = harvesterMax - harvesterBal;
            if (gas > nativeBal) {
                gas = nativeBal;
            }
            IWrappedNative(address(native)).withdraw(gas);
            (bool sent, ) = harvester.call{value: gas}("");
            require(sent, "Failed to send Ether");

            emit SendHarvesterGas(gas);
        }
    }

    /// @dev Swap to required treasury tokens and send the treasury fees onto the treasury
    function _distributeTreasuryFee() private {
        uint256 treasuryFeeAmount = native.balanceOf(address(this)) * treasuryFee / DIVISOR;

        for (uint i; i < treasuryTokens.tokens.length; ++i) {
            address token = treasuryTokens.tokens[i];
            uint256 amount = treasuryFeeAmount
                * treasuryTokens.allocPoint[token] 
                / treasuryTokens.totalAllocPoint;

            if (amount == 0) continue;
            if (token != address(native)) {
                amount = IBeefySwapper(swapper).swap(address(native), token, amount);
                if (amount == 0) continue;
            }

            IERC20Upgradeable(token).safeTransfer(treasury, amount);
            emit DistributeTreasuryFee(token, amount);
        }
    }

    /// @dev Swap to required reward tokens and notify the reward pool
    function _notifyRewardPool() private {
        uint256 rewardPoolAmount = native.balanceOf(address(this));

        for (uint i; i < rewardTokens.tokens.length; ++i) {
            address token = rewardTokens.tokens[i];
            uint256 amount = rewardPoolAmount
                * rewardTokens.allocPoint[token]
                / rewardTokens.totalAllocPoint;

            if (amount == 0) continue;
            if (token != address(native)) {
                amount = IBeefySwapper(swapper).swap(address(native), token, amount);
                if (amount == 0) continue;
            }

            IBeefyRewardPool(rewardPool).notifyRewardAmount(token, amount, duration);
            emit NotifyRewardPool(token, amount, duration);
        }
    }

    /* ----------------------------------- VARIABLE SETTERS ----------------------------------- */

    /// @notice Adjust which tokens and how much the harvest should swap the treasury fee to
    /// @param _token Address of the token to send to the treasury
    /// @param _allocPoint How much to swap into the particular token from the treasury fee
    function setTreasuryAllocPoint(address _token, uint256 _allocPoint) external onlyOwner {
        if (treasuryTokens.allocPoint[_token] > 0 && _allocPoint == 0) {
            address endToken = treasuryTokens.tokens[treasuryTokens.tokens.length - 1];
            treasuryTokens.index[endToken] = treasuryTokens.index[_token];
            treasuryTokens.tokens[treasuryTokens.index[endToken]] = endToken;
            treasuryTokens.tokens.pop();
        } else if (treasuryTokens.allocPoint[_token] == 0 && _allocPoint > 0) {
            treasuryTokens.index[_token] = treasuryTokens.tokens.length;
            treasuryTokens.tokens.push(_token);
        }

        treasuryTokens.totalAllocPoint -= treasuryTokens.allocPoint[_token];
        treasuryTokens.totalAllocPoint += _allocPoint;
        treasuryTokens.allocPoint[_token] = _allocPoint;
    }

    /// @notice Adjust which tokens and how much the harvest should swap the reward pool fee to
    /// @param _token Address of the token to send to the reward pool
    /// @param _allocPoint How much to swap into the particular token from the reward pool fee 
    function setRewardAllocPoint(address _token, uint256 _allocPoint) external onlyOwner {
        if (rewardTokens.allocPoint[_token] > 0 && _allocPoint == 0) {
            address endToken = rewardTokens.tokens[rewardTokens.tokens.length - 1];            
            rewardTokens.index[endToken] = rewardTokens.index[_token];
            rewardTokens.tokens[rewardTokens.index[endToken]] = endToken;
            rewardTokens.tokens.pop();
        } else if (rewardTokens.allocPoint[_token] == 0 && _allocPoint > 0) {
            rewardTokens.index[_token] = rewardTokens.tokens.length;
            rewardTokens.tokens.push(_token);
            IERC20Upgradeable(_token).forceApprove(rewardPool, type(uint).max);
        }

        rewardTokens.totalAllocPoint -= rewardTokens.allocPoint[_token];
        rewardTokens.totalAllocPoint += _allocPoint;
        rewardTokens.allocPoint[_token] = _allocPoint;
    }

    /// @notice Set the reward pool
    /// @param _rewardPool New reward pool address
    function setRewardPool(address _rewardPool) external onlyOwner {
        rewardPool = _rewardPool;
        emit SetRewardPool(_rewardPool);
    }

    /// @notice Set the treasury
    /// @param _treasury New treasury address
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit SetTreasury(_treasury);
    }

    /// @notice Set whether the harvester should be sent gas
    /// @param _sendGas Whether the harvester should be sent gas
    function setSendHarvesterGas(bool _sendGas) external onlyOwner {
        sendHarvesterGas = _sendGas;
        emit SetSendHarvesterGas(_sendGas);
    }

    /// @notice Set the harvester and the minimum operating gas level of the harvester
    /// @param _harvester New harvester address
    /// @param _harvesterMax New minimum operating gas level of the harvester
    function setHarvesterConfig(address _harvester, uint256 _harvesterMax) external onlyOwner {
        harvester = _harvester;
        harvesterMax = _harvesterMax;
        emit SetHarvester(_harvester, _harvesterMax);
    }

    /// @notice Set the swapper
    /// @param _swapper New swapper address
    function setSwapper(address _swapper) external onlyOwner {
        native.approve(swapper, 0);
        swapper = _swapper;
        native.forceApprove(swapper, type(uint).max);
        emit SetSwapper(_swapper);
    }

    /// @notice Set the treasury fee
    /// @param _treasuryFee New treasury fee split
    function setTreasuryFee(uint256 _treasuryFee) external onlyOwner {
        if (_treasuryFee > DIVISOR) _treasuryFee = DIVISOR;
        treasuryFee = _treasuryFee;
        emit SetTreasuryFee(_treasuryFee);
    }

    /// @notice Set the duration of the reward distribution
    /// @param _duration New duration of the reward distribution
    function setDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
        emit SetDuration(_duration);
    }

    /* ------------------------------------- SWEEP TOKENS ------------------------------------- */

    /// @notice Rescue an unsupported token
    /// @param _token Address of the token
    /// @param _recipient Address to send the token to
    function rescueTokens(address _token, address _recipient) external onlyOwner {
        require(_token != address(native), "!safe");

        uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(_recipient, amount);
        emit RescueTokens(_token, _recipient);
    }

    /// @notice Support unwrapped native
    receive() external payable {}
}
