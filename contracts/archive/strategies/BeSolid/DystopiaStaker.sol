// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/token/ERC721/IERC721Receiver.sol";

import "./IDystVoter.sol";
import "./IVeDyst.sol";
import "./BeSolidManager.sol";

interface IDystopiaBoostedStrategy {
    function want() external view returns (IERC20);
    function gauge() external view returns (address);
}
interface IVeDist {
    function claim(uint256 tokenId) external returns (uint);
}

interface IGauge {
    function getReward(address user, address[] calldata tokens) external;
    function getReward(uint256 id, address[] calldata tokens) external;
    function deposit(uint amount, uint tokenId) external;
    function withdraw(uint amount) external;
    function balanceOf(address user) external view returns (uint);
}

contract DystopiaStaker is BeSolidManager,  ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Addresses used 
    IDystVoter public dystVoter;
    IVeDyst public veToken;
    IVeDist public veDist;
    uint256 public veTokenId;
    IERC20 public want;
    address public treasury;

     // Strategy mapping 
    mapping(address => address) public whitelistedStrategy;
    mapping(address => address) public replacementStrategy;

    event CreateLock(address indexed user, uint256 veTokenId, uint256 amount, uint256 unlockTime);
    event IncreaseTime(address indexed user, uint256 veTokenId, uint256 unlockTime);
    event ClaimVeEmissions(address indexed user, uint256 veTokenId, uint256 amount);
    event ClaimRewards(address indexed user, address gauges, address[] tokens);
    event TransferVeToken(address indexed user, address to, uint256 veTokenId);

    constructor(
        address _dystVoter,
        address _veDist,
        address _treasury,
        address _keeper,
        address _voter
    ) BeSolidManager(_keeper, _voter) {
        dystVoter = IDystVoter(_dystVoter);
        veToken = IVeDyst(dystVoter.ve());
        want = IERC20(veToken.token());
        veDist = IVeDist(_veDist);
        treasury = _treasury;

        want.safeApprove(address(veToken), type(uint).max);
    }

    
    // Checks that caller is the strategy assigned to a specific gauge.
    modifier onlyWhitelist(address _gauge) {
        require(whitelistedStrategy[_gauge] == msg.sender, "!whitelisted");
        _;
    }

    //  --- Pass Through Contract Functions Below ---

    // Pass through a deposit to a boosted gauge
    function deposit(address _gauge, uint256 _amount) external onlyWhitelist(_gauge) {
        // Grab needed info
        IERC20 _underlying = IDystopiaBoostedStrategy(msg.sender).want();
        // Take before balances snapshot and transfer want from strat
        _underlying.safeTransferFrom(msg.sender, address(this), _amount);
        IGauge(_gauge).deposit(_amount, veTokenId);
    }

    // Pass through a withdrawal from boosted chef
    function withdraw(address _gauge, uint256 _amount) external onlyWhitelist(_gauge) {
        // Grab needed pool info
        IERC20 _underlying = IDystopiaBoostedStrategy(msg.sender).want(); 
        uint256 _before = IERC20(_underlying).balanceOf(address(this));       
        IGauge(_gauge).withdraw( _amount);
        uint256 _balance = _underlying.balanceOf(address(this)) - _before;
        _underlying.safeTransfer(msg.sender, _balance);
    }

     // Get Rewards and send to strat
    function harvestRewards(address _gauge, address[] calldata tokens) external onlyWhitelist(_gauge) {
        IGauge(_gauge).getReward(address(this), tokens);
        for (uint i; i < tokens.length;) {
            IERC20(tokens[i]).safeTransfer(msg.sender, IERC20(tokens[i]).balanceOf(address(this)));
            unchecked { ++i; }
        }
    }

    /**
     * @dev Whitelists a strategy address to interact with the Boosted Chef and gives approvals.
     * @param _strategy new strategy address.
     */
    function whitelistStrategy(address _strategy) external onlyManager {
        IERC20 _want = IDystopiaBoostedStrategy(_strategy).want();
        address _gauge = IDystopiaBoostedStrategy(_strategy).gauge();
        uint256 stratBal = IGauge(_gauge).balanceOf(address(this));
        require(stratBal == 0, "!inactive");

        _want.safeApprove(_gauge, 0);
        _want.safeApprove(_gauge, type(uint256).max);
        whitelistedStrategy[_gauge] = _strategy;
    }

    /**
     * @dev Removes a strategy address from the whitelist and remove approvals.
     * @param _strategy remove strategy address from whitelist.
     */
    function blacklistStrategy(address _strategy) external onlyManager {
        IERC20 _want = IDystopiaBoostedStrategy(_strategy).want();
        address _gauge = IDystopiaBoostedStrategy(_strategy).gauge();
        _want.safeApprove(_gauge, 0);
        whitelistedStrategy[_gauge] = address(0);
    }

    /**
     * @dev Prepare a strategy to be retired and replaced with another.
     * @param _oldStrategy strategy to be replaced.
     * @param _newStrategy strategy to be implemented.
     */
    function proposeStrategy(address _oldStrategy, address _newStrategy) external onlyManager {
        require(IDystopiaBoostedStrategy(_oldStrategy).gauge() == IDystopiaBoostedStrategy(_newStrategy).gauge(), "!gauge");
        replacementStrategy[_oldStrategy] = _newStrategy;
    }

   
    function upgradeStrategy(address _gauge) external onlyWhitelist(_gauge) {
        whitelistedStrategy[_gauge] = replacementStrategy[msg.sender];
    }

    // --- Vote Related Functions ---

    // claim veToken emissions and increases locked amount in veToken
    function claimVeEmissions() public {
        uint256 _amount = veDist.claim(veTokenId);
        emit ClaimVeEmissions(msg.sender, veTokenId, _amount);
    }

    // vote for emission weights
    function vote(address[] calldata _tokenVote, int256[] calldata _weights) external onlyVoter {
        claimVeEmissions();
        dystVoter.vote(veTokenId, _tokenVote, _weights);
    }

    // reset current votes
    function resetVote() external onlyVoter {
        dystVoter.reset(veTokenId);
    }

    function claimMultipleOwnerRewards(address[] calldata _gauges, address[][] calldata _tokens) external onlyManager {
        for (uint i; i < _gauges.length;) {
            claimOwnerRewards(_gauges[i], _tokens[i]);
            unchecked { ++i; }
        }
    }

    // claim owner rewards such as trading fees and bribes from gauges, transferred to treasury
    function claimOwnerRewards(address _gauge, address[] memory _tokens) public onlyManager {
            IGauge(_gauge).getReward(veTokenId, _tokens);
            for (uint i; i < _tokens.length;) {
                address _reward = _tokens[i];
                uint256 _rewardBal = IERC20(_reward).balanceOf(address(this));

                if (_rewardBal > 0) {
                    IERC20(_reward).safeTransfer(treasury, _rewardBal);
                }
                unchecked { ++i; }
            }

        emit ClaimRewards(msg.sender, _gauge, _tokens);
    }

    // whitelist new token
    function whitelist(address _token) external onlyManager {
        dystVoter.whitelist(_token, veTokenId);
    }


    // --- Token Management ---

    // create a new veToken if none is assigned to this address
    function createLock(uint256 _amount, uint256 _lock_duration, bool init) external onlyManager {
        require(veTokenId == 0, "veToken > 0");

        if (init) {
            veTokenId = veToken.tokenOfOwnerByIndex(msg.sender, 0);
            veToken.safeTransferFrom(msg.sender, address(this), veTokenId);
        } else {
            require(_amount > 0, "amount == 0");
            want.safeTransferFrom(address(msg.sender), address(this), _amount);
            veTokenId = veToken.createLock(_amount, _lock_duration);

            emit CreateLock(msg.sender, veTokenId, _amount, _lock_duration);
        }
    }

    // merge voting power of two veTokens by burning the _from veToken, _from must be detached and not voted with
    function merge(uint256 _fromId) external {
        require(_fromId != veTokenId, "cannot burn main veTokenId");
        veToken.safeTransferFrom(msg.sender, address(this), _fromId);
        veToken.merge(_fromId, veTokenId);
    }

    // extend lock time for veToken to increase voting power
    function increaseUnlockTime(uint256 _lock_duration) external onlyManager {
        veToken.increaseUnlockTime(veTokenId, _lock_duration);
        emit IncreaseTime(msg.sender, veTokenId, _lock_duration);
    }

    // transfer veToken to another address, must be detached from all gauges first
    function transferVeToken(address _to) external onlyOwner {
        uint256 transferId = veTokenId;
        veTokenId = 0;
        veToken.safeTransferFrom(address(this), _to, transferId);
        

        emit TransferVeToken(msg.sender, _to, transferId);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    // confirmation required for receiving veToken to smart contract
    function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata data
    ) external view returns (bytes4) {
        operator;
        from;
        tokenId;
        data;
        require(msg.sender == address(veToken), "!veToken");
        return bytes4(keccak256("onERC721Received(address,address,uint,bytes)"));
    }
}