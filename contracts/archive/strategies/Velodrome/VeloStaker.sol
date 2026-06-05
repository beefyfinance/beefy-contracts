// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/token/ERC721/IERC721Receiver.sol";

import "../BeSolid/BeSolidStaker.sol";
import "../../interfaces/common/ISolidlyRouter.sol";

interface IRewardPool {
    function notifyRewardAmount(uint256 reward) external;
}

interface ISolidlyGauge {
    function getReward(uint256 tokenId, address[] memory rewards) external;
}


contract VeloStaker is ERC20, BeSolidStaker {
    using SafeERC20 for IERC20;

    // Needed addresses
    IRewardPool public rewardPool;
    address[] public activeVoteLps;
    ISolidlyRouter public router;

    // Voted Gauges
    struct Gauges {
        address bribeGauge;
        address feeGauge;
        address[] bribeTokens;
        address[] feeTokens;
    }

    // Mapping our reward token to a route 
    mapping (address => ISolidlyRouter.Routes[]) public routes;
    mapping (address => bool) public lpIntialized;
    mapping (address => Gauges) public gauges;

    // Events
    event NewRewardPool(address oldPool, address newPool);
    event NewRouter(address oldRouter, address newRouter);
    event AddedGauge(address bribeGauge, address feeGauge, address[] bribeTokens, address[] feeTokens);
    event AddedRewardToken(address token);
    event RewardsHarvested(uint256 amount);
    
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _reserveRate,
        address _solidVoter,
        address _keeper,
        address _voter,
        address _rewardPool, 
        address _router
    ) BeSolidStaker(
        _name,
        _symbol,
        _reserveRate,
        _solidVoter,
        _keeper,
        _voter
    ) {
       rewardPool = IRewardPool(_rewardPool);
       router = ISolidlyRouter(_router);
    }

    // Set our reward Pool to send our earned Velo
    function setRewardPool(address _rewardPool) external onlyOwner {
        emit NewRewardPool(address(rewardPool), _rewardPool);
        rewardPool = IRewardPool(_rewardPool);
    }

    // Set our router to exchange our rewards
    function setRouter(address _router) external onlyOwner {
        emit NewRouter(address(router), _router);
        router = ISolidlyRouter(_router);
    }

    // vote for emission weights
    function vote(address[] calldata _tokenVote, uint256[] calldata _weights) external override onlyVoter {
        // Check to make sure we set up our rewards
        for (uint i; i < _tokenVote.length; ++i) {
            require(lpIntialized[_tokenVote[i]], "lp not lpIntialized");
        }

        activeVoteLps = _tokenVote;
        // We claim first to maximize our voting power.
        claimVeEmissions();
        solidVoter.vote(tokenId, _tokenVote, _weights);
    }

    // Add gauge
    function addGauge(address _lp, address[] calldata _bribeTokens, address[] calldata _feeTokens ) external onlyManager {
        address gauge = solidVoter.gauges(_lp);
        gauges[_lp] = Gauges(
            solidVoter.external_bribes(gauge),
            solidVoter.internal_bribes(gauge),
            _bribeTokens,
            _feeTokens
            );
        lpIntialized[_lp] = true;
        emit AddedGauge(solidVoter.external_bribes(_lp), solidVoter.internal_bribes(_lp), _bribeTokens, _feeTokens);
    }

    // Delete a reward token 
    function deleteRewardToken(address _token) external onlyManager {
        delete routes[_token];
    }

     // Add reward token
    function addRewardToken(ISolidlyRouter.Routes[] memory _route) external onlyManager {
        for (uint i; i < _route.length; ++i) {
            routes[_route[0].from].push(_route[i]);
        }
        
        IERC20(_route[0].from).safeApprove(address(router), 0);
        IERC20(_route[0].from).safeApprove(address(router), type(uint256).max);
        emit AddedRewardToken(_route[0].from);
    }
   

    // claim owner rewards such as trading fees and bribes from gauges swap to velo, notify reward pool
    function harvest() external {
       for (uint i; i < activeVoteLps.length; ++i) {
            Gauges storage rewardsGauge = gauges[activeVoteLps[i]];
            ISolidlyGauge(rewardsGauge.bribeGauge).getReward(tokenId, rewardsGauge.bribeTokens);
            ISolidlyGauge(rewardsGauge.feeGauge).getReward(tokenId, rewardsGauge.feeTokens);
            
            for (uint j; j < rewardsGauge.bribeTokens.length; ++j) {
                uint256 tokenBal = IERC20(rewardsGauge.bribeTokens[j]).balanceOf(address(this));
                if (tokenBal > 0 && rewardsGauge.bribeTokens[j] != address(want)) {
                    router.swapExactTokensForTokens(tokenBal, 0, routes[rewardsGauge.bribeTokens[j]], address(this), block.timestamp);
                }
            }

            for (uint k; k < rewardsGauge.feeTokens.length; ++k) {
                uint256 tokenBal = IERC20(rewardsGauge.feeTokens[k]).balanceOf(address(this));
                if (tokenBal > 0 && rewardsGauge.feeTokens[k] != address(want)) {
                    router.swapExactTokensForTokens(tokenBal, 0, routes[rewardsGauge.feeTokens[k]], address(this), block.timestamp);
                }
            }
            
       }

        uint256 rewardAmt = totalWant() - totalSupply();
        if (rewardAmt > 0) {
            want.safeTransfer(address(rewardPool), rewardAmt);
            rewardPool.notifyRewardAmount(rewardAmt);
            emit RewardsHarvested(rewardAmt);
        }
    }
}