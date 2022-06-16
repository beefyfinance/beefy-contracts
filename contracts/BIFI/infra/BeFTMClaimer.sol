//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/access/Ownable.sol";
import "@openzeppelin-4/contracts/security/Pausable.sol";

import "./OpsReady.sol";
import "../interfaces/common/IOps.sol";

interface IBeFTMRewardPool {
    function claimAndNotify() external;
}

contract BeFTMClaimer is OpsReady, Ownable, Pausable {
    using SafeERC20 for IERC20;

    IBeFTMRewardPool public constant beFtmRewardPool =
        IBeFTMRewardPool(0xE00D25938671525C2542A689e42D1cfA56De5888);
    uint256 public lastClaim;

    uint256 public maxGasPriceInGwei; //for Gelato tasks
    bytes32 public taskId; //Gelato taskId

    constructor(address _ops) OpsReady(_ops) {
        maxGasPriceInGwei = 200; //default 200gwei
    }

    //Distribution methods
    function gelatoClaim() external onlyOps whenNotPaused {
        require(tx.gasprice < maxGasPriceInGwei * 1 gwei, "Gas price too high");
        _claim();
        (uint256 feeAmount, ) = IOps(ops).getFeeDetails();
        _payTxFee(feeAmount);
    }

    function claim() external {
        _claim();
    }

    function _claim() internal {
        require(block.timestamp > lastClaim + 1 days, "Call Once a Day");
        beFtmRewardPool.claimAndNotify();
        lastClaim = block.timestamp;
    }

    function setMaxGasPriceInGwei(uint256 _maxGasPriceInGwei)
        external
        onlyOwner
    {
        maxGasPriceInGwei = _maxGasPriceInGwei;
    }

    //Gelato Task Settings
    function createGelatoTask() external onlyOwner {
        require(taskId == bytes4(""), "Task already exists");
        bytes4 _execSelector = bytes4(
            abi.encodeWithSignature("gelatoClaim()")
        );
        bytes memory resolverData = abi.encodeWithSignature("gelatoResolver()");
        taskId = IOps(ops).createTaskNoPrepayment(
            address(this),
            _execSelector,
            address(this),
            resolverData,
            ETH
        );
    }

    function cancelGelatoTask() external onlyOwner {
        IOps(ops).cancelTask(taskId);
        delete taskId;
    }

    /**
     * @notice Gelato resolver that always returns true with execPayload
     */
    function gelatoResolver()
        external
        pure
        returns (bool canExec, bytes memory execPayload)
    {
        canExec = true;
        execPayload = abi.encodeWithSignature("gelatoDistribute()");
    }

    //Recovery
    function recoverToken(address token, bool native) external onlyOwner {
        if (native) {
            (bool success, ) = owner().call{value: address(this).balance}("");
            require(success, "Native transfer failed");
        } else {
            uint256 tokenBal = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(owner(), tokenBal);
        }
    }

    receive() external payable {}
}