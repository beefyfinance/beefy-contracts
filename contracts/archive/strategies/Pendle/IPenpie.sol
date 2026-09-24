// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IPendleStaking {
    function masterPenpie() external view returns (address);
    function pools(address _market) external view returns (address market, address rewarder, address helper, address receiptToken, uint256 lastHarvestTime, bool isActive);
    function harvestTimeGap() external view returns (uint);
    function harvestMarketReward(address _market, address _caller, uint256 _minEthRecive) external;
}

interface IPoolHelper {
    function depositMarket(address _market, uint256 _amount) external;
    function withdrawMarket(address _market, uint256 _amount) external;
}

interface IMasterPenpie {
    function multiclaimSpecPNP(address[] calldata _stakingTokens, address[][] memory _rewards, bool _withPNP) external;
    function multiclaimFor(address[] calldata _stakingTokens, address[][] memory _rewardTokens, address _account) external;
}