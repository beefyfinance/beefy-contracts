// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Common/BaseAllToNativeFactoryStrat.sol";
import "./IPenpie.sol";
import {IMerklClaimer} from "../../interfaces/merkl/IMerklClaimer.sol";

contract StrategyPenpieMerkl is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IPoolHelper public poolHelper;
    IMasterPenpie public masterPenpie;
    IPendleStaking public pendleStaking;
    address public receiptToken;
    address[] public claimTokens;
    bool public claimPNP;
    bool public skipHarvestMarket;

    function initialize(
        IPendleStaking _pendleStaking,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer  {
        pendleStaking = _pendleStaking;
        masterPenpie = IMasterPenpie(pendleStaking.masterPenpie());
        (,, address _poolHelper, address _receiptToken,,) = pendleStaking.pools(_addresses.want);
        poolHelper = IPoolHelper(_poolHelper);
        receiptToken = _receiptToken;

        __BaseStrategy_init(_addresses, _rewards);
        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "Penpie";
    }

    function balanceOfPool() public view override returns (uint) {
        return IERC20(receiptToken).balanceOf(address(this));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(pendleStaking), amount);
        poolHelper.depositMarket(want, amount);
    }

    function _withdraw(uint amount) internal override {
        poolHelper.withdrawMarket(want, amount);
    }

    function _emergencyWithdraw() internal override {
        uint bal = IERC20(receiptToken).balanceOf(address(this));
        if (bal > 0) {
            poolHelper.withdrawMarket(want, bal);
        }
    }

    function _claim() internal override {
        if (!skipHarvestMarket) {
            (,,,, uint lastHarvestTime,) = pendleStaking.pools(want);
            if ((block.timestamp - lastHarvestTime) > pendleStaking.harvestTimeGap()) {
                poolHelper.withdrawMarket(want, 0);
            }
        }
        address[] memory lps = new address[](1);
        address[][] memory tokens = new address[][](1);
        lps[0] = want;
        tokens[0] = claimTokens;
        masterPenpie.multiclaimSpecPNP(lps, tokens, claimPNP);
    }

    function _verifyRewardToken(address token) internal view override {
        require(token != receiptToken, "!receipt");
    }

    function setClaimPNP(bool _claimPNP) external onlyManager {
        claimPNP = _claimPNP;
    }

    function setClaimTokens(address[] calldata _tokens) external onlyManager {
        claimTokens = _tokens;
    }

    function setSkipHarvestMarket(bool _skip) external onlyManager {
        skipHarvestMarket = _skip;
    }

    function merklClaim(
        address claimer,
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external {
        IMerklClaimer(claimer).claim(users, tokens, amounts, proofs);
    }

}