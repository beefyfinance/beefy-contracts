// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/convex/IFxConvex.sol";
import "../../interfaces/curve/IRewardsGauge.sol";
import "../Common/BaseAllToNativeStrat.sol";

// f(x) protocol through Convex proxy
contract StrategyFxConvex is BaseAllToNativeStrat {

    // Tokens used
    address public constant NATIVE = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IFxnVoterProxy public constant voterProxy = IFxnVoterProxy(0xd11a4Ee017cA0BECA8FA45fF2abFe9C6267b7881);
    IPoolRegistry public constant poolRegistry = IPoolRegistry(0xdB95d646012bB87aC2E6CD63eAb2C42323c1F5AF);

    address public gauge; // fx gauge
    address public cvxVault; // convex proxy vault
    uint public pid; // convex booster poolId


    bool public claimFxRewards; // rewards from fx gauge
    address[] public claimTokenList; // filter claimable rewards on convex

    function initialize(
        uint _pid,
        address _depositToken,
        address[] calldata _rewards,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        (,address _gauge,address want,,) = poolRegistry.poolInfo(_pid);
        pid = _pid;
        gauge = _gauge;
        cvxVault = voterProxy.operator().createVault(_pid);
        claimFxRewards = true;

        __BaseStrategy_init(want, NATIVE, _rewards, _commonAddresses);
        setDepositToken(_depositToken);
    }

    function balanceOfPool() public view override returns (uint) {
        return IRewardsGauge(gauge).balanceOf(cvxVault);
    }

    function _deposit(uint amount) internal override {
        IConvexVault(cvxVault).deposit(amount);
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            IConvexVault(cvxVault).withdraw(amount);
        }
    }

    function _emergencyWithdraw() internal override {
        _withdraw(balanceOfPool());
    }

    function _claim() internal override {
        if (claimTokenList.length == 0) {
            IConvexVault(cvxVault).getReward(claimFxRewards);
        } else {
            IConvexVault(cvxVault).getReward(claimFxRewards, claimTokenList);
        }
    }

    function _verifyRewardToken(address token) internal view override {
        require(token != gauge, "!gauge");
        require(token != cvxVault, "!cvxVault");
    }

    function _giveAllowances() internal override {
        uint amount = type(uint).max;
        _approve(want, cvxVault, amount);
        _approve(native, unirouter, amount);
    }

    function _removeAllowances() internal override {
        _approve(want, cvxVault, 0);
        _approve(native, unirouter, 0);
    }

    function setClaimFxRewards(bool _claimFx) external onlyManager {
        claimFxRewards = _claimFx;
    }

    function setClaimTokenList(address[] calldata _tokenList) external onlyManager {
        claimTokenList = _tokenList;
    }


    // onlyOwner functions in convex vault proxy

    function transferTokens(address[] calldata _tokenList) external onlyOwner {
        //return any tokens in vault back to owner (strategy)
        IConvexVault(cvxVault).transferTokens(_tokenList);
    }

    function execute(address _to, uint256 _value, bytes calldata _data) external onlyOwner returns (bool, bytes memory) {
        //allow arbitrary calls. some function signatures and targets are blocked
        return IConvexVault(cvxVault).execute(_to, _value, _data);
    }
}
