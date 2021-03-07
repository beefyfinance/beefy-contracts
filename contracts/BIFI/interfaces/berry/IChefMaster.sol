pragma solidity ^0.6.0;

interface IChefMaster {
    function depositLPToken(uint256 _pid, uint256 _amount) external;
    function withdrawLPToken(uint256 _pid, uint256 _amount) external;
    function getPendingToken(uint256 _pid, address _user) external view returns (uint256);
    function getUserInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function mineLPToken(uint256 _pid) external;
}
