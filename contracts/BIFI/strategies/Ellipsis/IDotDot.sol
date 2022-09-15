// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IDotDotLpDepositor {
    struct Amounts {
        uint256 epx;
        uint256 ddd;
    }

    struct ExtraReward {
        address token;
        uint256 amount;
    }

    function depositTokens(address pool) external view returns (address);
    function userBalances(address user, address pool) external view returns (uint256);

    function deposit(address _user, address _token, uint256 _amount) external;
    function withdraw(address _receiver, address _token, uint256 _amount) external;

    function claimable(address _user, address[] calldata _tokens) external view returns (Amounts[] memory);
    function claimableExtraRewards(address user, address pool) external view returns (ExtraReward[] memory);
    function claim(address _receiver, address[] calldata _tokens, uint256 _maxBondAmount) external;
    function claimExtraRewards(address _receiver, address pool) external;
}

interface IDotDotBondedFeeDistributor {
    function claimable(address _user, address[] calldata _tokens) external view returns (uint256[] memory amounts);
    function claim(address _user, address[] calldata _tokens) external returns (uint256[] memory claimedAmounts);

    function bondedBalance(address _user) external view returns (uint256);
    function unbondableBalance(address _user) external view returns (uint256);
    function streamingBalances(address _user) external view returns (uint256 _claimable, uint256 _total);

    function initiateUnbondingStream(uint256 _amount) external returns (bool);
    function withdrawUnbondedTokens(address _receiver) external returns (bool);
}