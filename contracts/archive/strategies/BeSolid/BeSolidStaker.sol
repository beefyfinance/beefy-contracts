// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/token/ERC721/IERC721Receiver.sol";

import "./BeSolidManager.sol";
import "./IVoter.sol";
import "./IVeDist.sol";
import "./IVeToken.sol";

interface IMinter {
    function _rewards_distributor() external view returns (address);
}

contract BeSolidStaker is ERC20, BeSolidManager,  ReentrancyGuard {
    using SafeERC20 for IERC20;


    // Addresses used 
    IVoter public solidVoter;
    IVeToken public ve;
    IVeDist public veDist;

    // Want token and our NFT Token ID
    IERC20 public want;
    uint256 public tokenId;

    // Max Lock time, Max variable used for reserve split and the reserve rate. 
    uint16 public constant MAX = 10000;
    uint256 public constant MAX_LOCK = 364 days * 4;
    uint256 public reserveRate; 


    // Our on chain events.
    event CreateLock(address indexed user, uint256 veTokenId, uint256 amount, uint256 unlockTime);
    event Release(address indexed user, uint256 veTokenId, uint256 amount);
    event IncreaseTime(address indexed user, uint256 veTokenId, uint256 unlockTime);
    event DepositWant(uint256 amount);
    event Withdraw(uint256 amount);
    event ClaimVeEmissions(address indexed user, uint256 veTokenId, uint256 amount);
    event UpdatedReserveRate(uint256 newRate);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _reserveRate,
        address _solidVoter,
        address _keeper,
        address _voter
    ) ERC20( _name, _symbol) BeSolidManager(_keeper, _voter){
        reserveRate = _reserveRate;
        solidVoter = IVoter(_solidVoter);
        ve = IVeToken(solidVoter._ve());
        want = IERC20(ve.token());
        IMinter _minter = IMinter(solidVoter.minter());
        veDist = IVeDist(_minter._rewards_distributor());

        want.safeApprove(address(ve), type(uint256).max);
    }

    // Deposit all want for a user.
    function depositAll() external {
        _deposit(want.balanceOf(msg.sender));
    }

    // Deposit an amount of want.
    function deposit(uint256 _amount) external {
        _deposit(_amount);
    }

     // Internal: Deposits Want and mint beWant, checks for ve increase opportunities first. 
    function _deposit(uint256 _amount) internal nonReentrant whenNotPaused {
        lock();
        uint256 _pool = balanceOfWant();
        want.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = balanceOfWant();
        _amount = _after - _pool; // Additional check for deflationary tokens.

        if (_amount > 0) {
            _mint(msg.sender, _amount);
            emit DepositWant(totalWant());
        }
    }

    // Deposit more in ve and up locktime.
    function lock() public { 
        if (totalWant() > 0) {
            (,, bool shouldIncreaseLock) = lockInfo();
            if (balanceOfWant() > requiredReserve()) {
                uint256 availableBalance = balanceOfWant() - requiredReserve();
                ve.increase_amount(tokenId, availableBalance);
                if (shouldIncreaseLock) {
                    ve.increase_unlock_time(tokenId, MAX_LOCK);
                }
            } else {
                // Extend max lock
                if (shouldIncreaseLock) {
                    ve.increase_unlock_time(tokenId, MAX_LOCK);
                }
            }
        }
    }

    // Withdraw capable if we have enough Want in the contract. 
    function withdraw(uint256 _amount) external {
        require(_amount <= withdrawableBalance(), "Not enough Want");
            _burn(msg.sender, _amount);
            want.safeTransfer(msg.sender, _amount);
            emit Withdraw(totalWant());
    }

    // Total Want in ve contract and beVe contract. 
    function totalWant() public view returns (uint256) {
        return balanceOfWant() + balanceOfWantInVe();
    }

    // Our required Want held in the contract to enable withdraw capabilities.
    function requiredReserve() public view returns (uint256 reqReserve) {
        // We calculate allocation for reserve of the total staked in Ve.
        reqReserve = balanceOfWantInVe() * reserveRate / MAX;
    }

    // Calculate how much 'want' is held by this contract
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // What is our end lock and seconds remaining in lock? 
    function lockInfo() public view returns (uint256 endTime, uint256 secondsRemaining, bool shouldIncreaseLock) {
        (, endTime) = ve.locked(tokenId);
        uint256 unlockTime = (block.timestamp + MAX_LOCK) / 1 weeks * 1 weeks;
        secondsRemaining = endTime > block.timestamp ? endTime - block.timestamp : 0;
        shouldIncreaseLock = unlockTime > endTime ? true : false;
    }

    // Withdrawable Balance for users
    function withdrawableBalance() public view returns (uint256) {
        return balanceOfWant();
    }

    // How many want we got earning? 
    function balanceOfWantInVe() public view returns (uint256 wants) {
        (wants, ) = ve.locked(tokenId);
    }

    // Claim veToken emissions and increases locked amount in veToken
    function claimVeEmissions() public {
        uint256 _amount = veDist.claim(tokenId);
        emit ClaimVeEmissions(msg.sender, tokenId, _amount);
    }

    // Vote for emission weights.
    function vote(address[] calldata _tokenVote, uint256[] calldata _weights) external virtual onlyVoter {
        // We claim first to maximize our voting power.
        claimVeEmissions();
        solidVoter.vote(tokenId, _tokenVote, _weights);
    }

    // Reset current votes
    function resetVote() external onlyVoter {
        solidVoter.reset(tokenId);
    }

    // Create a new veToken if none is assigned to this address
    function createLock(uint256 _amount, uint256 _lock_duration) external onlyManager {
        require(tokenId == 0, "veToken > 0");
        require(_amount > 0, "amount == 0");

        want.safeTransferFrom(address(msg.sender), address(this), _amount);
        tokenId = ve.create_lock(_amount, _lock_duration);
        _mint(msg.sender, _amount);

        emit CreateLock(msg.sender, tokenId, _amount, _lock_duration);
    }

    // Release expired lock of a veToken owned by this address
    function release() external onlyOwner {
        (uint endTime,,) = lockInfo();
        require(endTime <= block.timestamp, "!Unlocked");
        ve.withdraw(tokenId);
      
        emit Release(msg.sender, tokenId, balanceOfWant());
    }

    // Whitelist new token
    function whitelist(address _token) external onlyManager {
        solidVoter.whitelist(_token, tokenId);
    }

     // Adjust reserve rate 
    function adjustReserve(uint256 _rate) external onlyOwner { 
        require(_rate <= MAX, "Higher than max");
        reserveRate = _rate;
        emit UpdatedReserveRate(_rate);
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

    // onfirmation required for receiving veToken to smart contract
    function onERC721Received(
        address operator,
        address from,
        uint _tokenId,
        bytes calldata data
    ) external view returns (bytes4) {
        operator;
        from;
        _tokenId;
        data;
        require(msg.sender == address(ve), "!veToken");
        return bytes4(keccak256("onERC721Received(address,address,uint,bytes)"));
    }
}