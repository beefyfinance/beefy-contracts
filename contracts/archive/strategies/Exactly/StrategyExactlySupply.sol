// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../utils/UniswapV3Utils.sol";
import "../../interfaces/common/ISolidlyRouter.sol";
import "../../interfaces/exactly/IExactlyMarket.sol";
import "../../interfaces/exactly/IExactlyRewardsController.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyExactlySupply is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    struct Routes {
        address[] nativeToWantRoute;
        uint24[] nativeToWantFees;
    }

    struct RewardRoute {
        bytes uniswapRoute;
        ISolidlyRouter.Route[] solidlyRoute;
    }

    // Tokens used
    address public want;
    address public native;
    address public eToken;
    address[] public rewards;

    // Third party contracts
    address public rewardsController;
    address public veloRouter;

    // Routes
    bytes public nativeToWantPath;
    mapping (address => RewardRoute) public rewardRoutes;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    /**
     * @dev Events that the contract emits
     */
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _eToken,
        address _rewardsController,
        address _veloRouter,
        Routes calldata _routes,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);

        eToken = _eToken;
        rewardsController = _rewardsController;
        veloRouter = _veloRouter;

        native = _routes.nativeToWantRoute[0];
        want = _routes.nativeToWantRoute[_routes.nativeToWantRoute.length - 1];

        nativeToWantPath = UniswapV3Utils.routeToPath(_routes.nativeToWantRoute, _routes.nativeToWantFees);

        _giveAllowances();
    }

    /**
     * @dev Puts the funds to work
     */
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IExactlyMarket(eToken).deposit(wantBal, address(this));
            emit Deposit(balanceOf());
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault
     * @param _amount How much {want} to withdraw.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();
        if (wantBal < _amount) {
            IExactlyMarket(eToken).withdraw(_amount - wantBal, address(this), address(this));
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal * withdrawalFee / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);
        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    /**
     * @dev Compounds earnings and charges performance fee
     */
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IExactlyRewardsController(rewardsController).claimAll(address(this));
        for (uint i; i < rewards.length;) {
            if (IERC20(rewards[i]).balanceOf(address(this)) > 0) {
                swapToNative();
                chargeFees(callFeeRecipient);
                swapToWant();
                uint256 wantHarvested = balanceOfWant();
                deposit();

                lastHarvest = block.timestamp;
                emit StratHarvest(msg.sender, wantHarvested, balanceOf());
                break;
            }
            unchecked { ++i; }
        }
    }

    function swapToNative() internal {
        for (uint i; i < rewards.length;) {
            uint256 bal = IERC20(rewards[i]).balanceOf(address(this));
            if (bal > 0) {
                if (rewardRoutes[rewards[i]].uniswapRoute.length != 0) {
                    UniswapV3Utils.swap(unirouter, rewardRoutes[rewards[i]].uniswapRoute, bal);
                } else {
                    ISolidlyRouter(veloRouter).swapExactTokensForTokens(bal, 0, rewardRoutes[rewards[i]].solidlyRoute, address(this), block.timestamp);
                }
            }
            unchecked { ++i; }
        }
    }

    /**
     * @dev Performance fees
     */
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    function swapToWant() internal {
        if (native != want) {
            uint256 toWant = IERC20(native).balanceOf(address(this));
            UniswapV3Utils.swap(unirouter, nativeToWantPath, toWant);
        }
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 supplyBal,) = IExactlyMarket(eToken).accountSnapshot(address(this));
        return supplyBal;
    }

    // returns rewards unharvested
    function rewardsAvailable() external view returns (uint256) {
        return IExactlyRewardsController(rewardsController).allClaimable(address(this), rewards[0]);
    }

    // native reward amount for calling harvest
    function callReward() external pure returns (uint256) {
        return 0;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        
        uint256 eTokenBal = IERC20(eToken).balanceOf(address(this));
        if (eTokenBal > 0) IExactlyMarket(eToken).redeem(eTokenBal, address(this), address(this));

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        uint256 eTokenBal = IERC20(eToken).balanceOf(address(this));
        if (eTokenBal > 0) IExactlyMarket(eToken).redeem(eTokenBal, address(this), address(this));

        pause();
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(eToken, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);
        for (uint i; i < rewards.length;) {
            address token = rewards[i];
            if (rewardRoutes[token].uniswapRoute.length != 0) {
                IERC20(token).safeApprove(unirouter, type(uint).max);
            } else {
                IERC20(token).safeApprove(veloRouter, type(uint).max);
            }
            unchecked { ++i; }
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(eToken, 0);
        IERC20(native).safeApprove(unirouter, 0);
        for (uint i; i < rewards.length;) {
            address token = rewards[i];
            if (rewardRoutes[token].uniswapRoute.length != 0) {
                IERC20(token).safeApprove(unirouter, 0);
            } else {
                IERC20(token).safeApprove(veloRouter, 0);
            }
            unchecked { ++i; }
        }
    }

    function nativeToWant() public view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(nativeToWantPath);
    }

    function rewardToNative(uint256 _id) public view returns (address[] memory) {
        if (rewardRoutes[rewards[_id]].uniswapRoute.length != 0) {
            return UniswapV3Utils.pathToRoute(rewardRoutes[rewards[_id]].uniswapRoute);
        } else {
            address[] memory route = new address[](rewardRoutes[rewards[_id]].solidlyRoute.length + 1);
            route[0] = rewardRoutes[rewards[_id]].solidlyRoute[0].from;
            for (uint i; i < rewardRoutes[rewards[_id]].solidlyRoute.length; ++i) {
                route[i + 1] = rewardRoutes[rewards[_id]].solidlyRoute[i].to;
            }
            return route;
        }
    }

    function addReward(address _token, bytes calldata _uniswapRoute, ISolidlyRouter.Route[] calldata _solidlyRoute) external onlyOwner {
        require(_token != want, "Reward is want");
        if (_uniswapRoute.length != 0) {
            IERC20(_token).safeApprove(unirouter, type(uint).max);
            rewardRoutes[_token].uniswapRoute = _uniswapRoute;
        } else {
            IERC20(_token).safeApprove(veloRouter, type(uint).max);
            for (uint i; i < _solidlyRoute.length; ++i) {
                rewardRoutes[_token].solidlyRoute.push(_solidlyRoute[i]);
            }
        }
        rewards.push(_token);
    }

    function resetRewards() external onlyManager {
        for (uint i; i < rewards.length;) {
            address token = rewards[i];
            if (rewardRoutes[token].uniswapRoute.length != 0) {
                IERC20(token).safeApprove(unirouter, 0);
            } else {
                IERC20(token).safeApprove(veloRouter, 0);
            }
            delete rewardRoutes[token];
            unchecked { ++i; }
        }
        delete rewards;
    }
}
