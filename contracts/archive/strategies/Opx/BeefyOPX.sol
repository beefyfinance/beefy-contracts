// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";

import "./OpxManager.sol";
import "./IVeOpx.sol";
import "./IVeOpxRoom.sol";
import "./IOpxNFT.sol";
import "./IVoterOpx.sol";

contract BeefyOPX is ERC20Upgradeable, ReentrancyGuardUpgradeable, OpxManager {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Addresses used 
    IVeOpx public ve;
    IVeOpxRoom public veOpxRoom;
    IOpxNFT public opxNFT;
    IVoterOpx public voter;

    // Want token and our NFT Token ID
    IERC20Upgradeable public want;
    IERC20Upgradeable public reward;
    uint256 public tokenId;

    // Max Lock time, Max variable used for reserve split and the reserve rate. 
    uint16 public constant MAX = 10000;
    uint256 public constant MAX_LOCK = 42 weeks;
    uint256 public reserveRate;

    // Our on chain events.
    event Deposit(uint256 tvl);
    event LockAmountIncreased(uint256 amount);
    event LockTimeIncreased(uint256 endTime);
    event Withdraw(uint256 tvl);
    event Harvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Vote(uint256[] weights);
    event VoteReset();
    event InitializeTokenId(uint256 tokenId);
    event SetVeOpxRoom(address room);
    event Release(uint256 amount);
    event ReleaseNFT(address receiver, uint256 tokenId);
    event EmergencyWithdraw(uint256 amount);
    event UpdatedReserveRate(uint256 newRate);

    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _reserveRate,
        address _ve,
        address _veOpxRoom,
        address _keeper,
        address _rewardPool
    ) public initializer {
        __OpxManager_init(_keeper, _rewardPool);
        __ERC20_init(_name, _symbol);
        __ReentrancyGuard_init();

        reserveRate = _reserveRate;
        ve = IVeOpx(_ve);
        veOpxRoom = IVeOpxRoom(_veOpxRoom);

        opxNFT = IOpxNFT(ve.opxNFT());
        voter = IVoterOpx(ve.voter());
        want = IERC20Upgradeable(ve.token());
        reward = IERC20Upgradeable(veOpxRoom.reward());
           
        want.safeApprove(address(ve), type(uint256).max);
        opxNFT.setApprovalForAll(address(ve), true);
    }

    // Deposit all want for a user
    function depositAll() external {
        _deposit(want.balanceOf(msg.sender));
    }

    // Deposit an amount of want
    function deposit(uint256 _amount) external {
        _deposit(_amount);
    }

    // Deposits Want and mint beWant, checks for ve increase opportunities first
    function _deposit(uint256 _amount) internal nonReentrant whenNotPaused {
        lock();
        uint256 _pool = balanceOfWant();
        want.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = balanceOfWant();
        _amount = _after - _pool; // Additional check for deflationary tokens

        if (_amount > 0) {
            _mint(msg.sender, _amount);
            emit Deposit(totalWant());
        }
    }

    // Deposit more in ve and up locktime
    function lock() public whenNotPaused {
        if (balanceOfWant() > requiredReserve()) {
            uint256 availableBalance = balanceOfWant() - requiredReserve();
            if (availableBalance > ve.minLockedAmount()) {
                ve.increase_amount(tokenId, availableBalance);
                emit LockAmountIncreased(availableBalance);
            }
        }

        (,, bool shouldIncreaseLock) = lockInfo();
        if (shouldIncreaseLock) {
            ve.increase_unlock_time(tokenId, MAX_LOCK);
            (, uint256 endTime) = ve.locked(tokenId);
            emit LockTimeIncreased(endTime);
        }
    }

    // What is our end lock and seconds remaining in lock? 
    function lockInfo() public view returns (uint256 endTime, uint256 secondsRemaining, bool shouldIncreaseLock) {
        (, endTime) = ve.locked(tokenId);
        uint256 unlockTime = (block.timestamp + MAX_LOCK) / 1 weeks * 1 weeks;
        secondsRemaining = endTime > block.timestamp ? endTime - block.timestamp : 0;
        shouldIncreaseLock = unlockTime > endTime ? true : false;
    }

    // Withdraw capable if we have enough Want in the contract
    function withdraw(uint256 _amount) external {
        require(_amount <= withdrawableBalance(), "Not enough Want");
        _burn(msg.sender, _amount);
        want.safeTransfer(msg.sender, _amount);
        emit Withdraw(totalWant());
    }

    // Total Want in ve contract and beVe contract
    function totalWant() public view returns (uint256) {
        return balanceOfWant() + balanceOfWantInVe();
    }

    // Our required Want held in the contract to enable withdraw capabilities
    function requiredReserve() public view returns (uint256) {
        return balanceOfWantInVe() * reserveRate / MAX;
    }

    // Calculate how much 'want' is held by this contract
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // Withdrawable Balance for users
    function withdrawableBalance() public view returns (uint256) {
        return balanceOfWant();
    }

    // How many want we got earning?
    function balanceOfWantInVe() public view returns (uint256) {
        (int128 wants, ) = ve.locked(tokenId);
        return uint256(int256(wants));
    }

    // Claim veToken rewards and notifies reward pool
    function harvest() public {
        veOpxRoom.claimReward();
        uint256 rewardBal = reward.balanceOf(address(this));
        if (rewardBal > 0) {
            reward.safeTransfer(address(rewardPool), rewardBal);
            rewardPool.notifyRewardAmount(rewardBal);
            emit Harvest(msg.sender, rewardBal, totalWant());
        }
    }

    // Vote for emission weights
    function vote(uint256[] calldata _weights) external onlyManager {
        voter.vote(tokenId, _weights);
        emit Vote(_weights);
    }

    // Reset current votes
    function resetVote() external onlyManager {
        voter.reset(tokenId);
        emit VoteReset();
    }

    // Pause deposits
    function pause() public onlyManager {
        _pause();
        want.safeApprove(address(ve), 0);
    }

    // Unpause deposits
    function unpause() external onlyManager {
        _unpause();
        want.safeApprove(address(ve), type(uint256).max);
    }

    // Adjust reserve rate 
    function adjustReserve(uint256 _rate) external onlyOwner { 
        require(_rate <= MAX, "Higher than max");
        reserveRate = _rate;
        emit UpdatedReserveRate(_rate);
    }

    // Set new ve reward pool
    function setVeOpxRoom(address _veOpxRoom) external onlyOwner {
        veOpxRoom.exit();
        veOpxRoom = IVeOpxRoom(_veOpxRoom);
        veOpxRoom.stake(tokenId);
        emit SetVeOpxRoom(_veOpxRoom);
    }

    // Release expired lock
    function release() external onlyOwner {
        veOpxRoom.exit();
        ve.withdraw(tokenId);
        emit Release(totalWant());
    }

    // Can release NFT only after releasing expired lock
    function releaseNFT(address _receiver) external onlyOwner {
        opxNFT.safeTransferFrom(address(this), _receiver, tokenId);
        emit ReleaseNFT(_receiver, tokenId);
    }

    // Emergency withdraw (penalty of 50%)
    function emergencyWithdraw() external onlyOwner {
        veOpxRoom.emergencyWithdraw();
        emit EmergencyWithdraw(totalWant());
    }

    // Initialize the contract, must release lock before initializing again
    function initializeTokenId(uint256 _tokenId, uint256 _amount) external onlyManager {
        opxNFT.safeTransferFrom(msg.sender, address(this), _tokenId);
        want.safeTransferFrom(msg.sender, address(this), _amount);

        ve.create_lock(_tokenId, _amount, MAX_LOCK);
        _mint(msg.sender, _amount);
        
        veOpxRoom.stake(_tokenId);
        tokenId = _tokenId;
        emit InitializeTokenId(_tokenId);
    }

    // Confirmation required for receiving NFT to smart contract
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }
}