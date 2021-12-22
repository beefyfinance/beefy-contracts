// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IOmnitradeCurve {
    event Approval(address indexed _owner,address indexed spender,uint256 value);
    event AssetIncluded(address indexed numeraire,address indexed reserve,uint256 weight);
    event AssimilatorIncluded(address indexed derivative,address indexed numeraire,address indexed reserve,address assimilator);
    event EmergencyAlarm(bool isEmergency);
    event FrozenSet(bool isFrozen);
    event OwnershipTransfered(address indexed previousOwner,address indexed newOwner);
    event ParametersSet(uint256 alpha,uint256 beta,uint256 delta,uint256 epsilon,uint256 lambda);
    event PartitionRedeemed(address indexed token,address indexed redeemer,uint256 value);
    event Trade(address indexed trader,address indexed origin,address indexed target,uint256 originAmount,uint256 targetAmount);
    event Transfer(address indexed from,address indexed to,uint256 value);
    event WhitelistingStopped();
    function allowance(address _owner,address _spender) external view returns (uint256 allowance_);
    function approve(address _spender,uint256 _amount) external  returns (bool success_);
    function assimilator(address _derivative) external view returns (address assimilator_);
    function balanceOf(address _account) external view returns (uint256 balance_);
    function curve() external view returns (int128 alpha, int128 beta, int128 delta, int128 epsilon, int128 lambda, uint256 totalSupply);
    function decimals() external view returns (uint8);
    function deposit(uint256 _deposit,uint256 _deadline) external  returns (uint256 , uint256[] memory);
    function depositWithWhitelist(uint256 index,address account,uint256 amount,bytes32[] memory merkleProof,uint256 _deposit,uint256 _deadline) external  returns (uint256 , uint256[] memory);
    function derivatives(uint256) external view returns (address);
    function emergency() external view returns (bool);
    function emergencyWithdraw(uint256 _curvesToBurn,uint256 _deadline) external  returns (uint256[] memory withdrawals_);
    function excludeDerivative(address _derivative) external;
    function frozen() external view returns (bool);
    function isWhitelisted(uint256 index,address account,uint256 amount,bytes32[] memory merkleProof) external view returns (bool);
    function liquidity() external view returns (uint256 total_, uint256[] memory individual_);
    function merkleRoot() external view returns (bytes32);
    function name() external view returns (string memory);
    function numeraires(uint256) external view returns (address);
    function originSwap(address _origin,address _target,uint256 _originAmount,uint256 _minTargetAmount,uint256 _deadline) external  returns (uint256 targetAmount_);
    function owner() external view returns (address);
    function reserves(uint256) external view returns (address);
    function setEmergency(bool _emergency) external;
    function setFrozen(bool _toFreezeOrNotToFreeze) external;
    function setParams(uint256 _alpha,uint256 _beta,uint256 _feeAtHalt,uint256 _epsilon,uint256 _lambda) external;
    function supportsInterface(bytes4 _interface) external pure returns (bool supports_);
    function symbol() external view returns (string memory);
    function targetSwap(address _origin,address _target,uint256 _maxOriginAmount,uint256 _targetAmount,uint256 _deadline) external  returns (uint256 originAmount_);
    function totalSupply() external view returns (uint256 totalSupply_);
    function transfer(address _recipient,uint256 _amount) external  returns (bool success_);
    function transferFrom(address _sender,address _recipient,uint256 _amount) external  returns (bool success_);
    function transferOwnership(address _newOwner) external;
    function turnOffWhitelisting() external;
    function viewCurve() external view returns (uint256 alpha_, uint256 beta_, uint256 delta_, uint256 epsilon_, uint256 lambda_);
    function viewDeposit(uint256 _deposit) external view returns (uint256 , uint256[] memory);
    function viewOriginSwap(address _origin,address _target,uint256 _originAmount) external view returns (uint256 targetAmount_);
    function viewTargetSwap(address _origin,address _target,uint256 _targetAmount) external view returns (uint256 originAmount_);
    function viewWithdraw(uint256 _curvesToBurn) external view returns (uint256[] memory);
    function whitelistedDeposited(address) external view returns (uint256);
    function whitelistingStage() external view returns (bool);
    function withdraw(uint256 _curvesToBurn,uint256 _deadline) external  returns (uint256[] memory withdrawals_);
}
