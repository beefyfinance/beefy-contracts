// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/beefy/IVault.sol";

/**
 * @title Yield Balancer
 * @author sirbeefalot & superbeefyboy
 * @dev It serves as a load balancer for multiple vaults that optimize the same asset.
 * Constrains:
 * - Subvaults that serve as workers can't charge withdraw fee.
 */
contract YieldBalancer is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public want;
    address public immutable vault;

    struct WorkerCandidate {
        address addr;
        uint proposedTime;
    }

    address[] public workers;
    WorkerCandidate[] public candidates;
    uint immutable approvalDelay;

    /**
     * @dev Used to protect vault users against vault hoping.
     * {WITHDRAWAL_FEE} - Fee taxed when a user withdraws funds. 10 === 0.1% fee.
     * {WITHDRAWAL_MAX} - Aux const used to safely calc the correct amounts.
     */
    uint constant public WITHDRAWAL_FEE = 10;
    uint constant public WITHDRAWAL_MAX = 10000;

    /**
        * @dev Events emitted. Deposit() and Withdrawal() are used by the management bot to know if 
        * an action that might break balance happened.
     */
    event CandidateProposed(address candidate);
    event CandidateAccepted(address candidate);
    event CandidateRejected(address candidate);
    event WorkerDeleted(address worker);
    event Deposit();
    event Withdrawal();

    /**
     * @notice Initializes the strategy
     * @param _want Address of the token to maximize.
     * @param _vault Address of the vault that will manage the strat.
     * @param _workers Array of vault addresses that will serve as workers.
     * @param _approvalDelay Seconds that have to pass before a candidate is added.
     */
    constructor(
        address _want,
        address _vault, 
        address[] memory _workers, 
        uint256 _approvalDelay
    ) public {
        want = _want;
        vault = _vault;
        workers = _workers;
        approvalDelay = _approvalDelay;

        _workerApproveAll(uint(-1));
    }

    //--- USER FUNCTIONS ---//

    /**
     * @notice Puts the funds to work.
     * @dev Will send all the funds to the main worker, at index 0.
     */
    function deposit() public whenNotPaused {
        _workerDeposit(0);

        emit Deposit();
    }

    /**
     * @dev It withdraws {want} from the workers and sends it to the vault.
     * @param amount how much {want} to withdraw.
     */
    function withdraw(uint amount) external {
        require(msg.sender == vault, "!vault");

        uint wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < amount) {
            for (uint8 i = 0; i < workers.length; i++) {
                uint workerBal = _workerBalance(i);
                if (workerBal < amount.sub(wantBal)) {
                    _workerWithdraw(i);
                    wantBal = IERC20(want).balanceOf(address(this));
                } else {
                    _workerPartialWithdraw(i, amount.sub(wantBal));
                    break;
                }
            }
        }

        wantBal = IERC20(want).balanceOf(address(this));
        uint _fee = wantBal.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
        IERC20(want).safeTransfer(vault, wantBal.sub(_fee));

        emit Withdrawal();
    }

    //--- FUNDS REBALANCE ---///

    /**
     * @dev Sends all funds from a vault to another one.
     * @param fromIndex Index of worker to take funds from. 
     * @param toIndex Index of worker where funds will go.
     */
    function rebalancePair(uint fromIndex, uint toIndex) external onlyOwner {
        require(fromIndex < workers.length, "!from");   
        require(toIndex < workers.length, "!to");   

        _workerWithdraw(fromIndex);
        _workerDeposit(toIndex);
    }

    /**
     * @dev Sends a subset funds from a vault to another one.
     * @param fromIndex Index of worker to take funds from. 
     * @param toIndex Index of worker where funds will go.
     * @param amount How much funds to send
     */
    function rebalancePairPartial(uint fromIndex, uint toIndex, uint amount) external onlyOwner {
        require(fromIndex < workers.length, "!from");   
        require(toIndex < workers.length, "!to");   

        _workerPartialWithdraw(fromIndex, amount);
        _workerDeposit(toIndex);
    }

    //--- CANDIDATE MANAGEMENT ---//

    /**
     * @dev Starts the process to add a new worker.
     * @param candidate Address of worker vault
     */
    function proposeCandidate(address candidate) external onlyOwner {
        candidates.push(WorkerCandidate({
            addr: candidate,
            proposedTime: now
        }));
            
        emit CandidateProposed(candidate);
    }

    /**
     * @dev Adds a candidate to the worker pool. Can only be done after {approvalDelay} has passed.
     * @param index Index of candidate in the {candidates} array.
     */
    function acceptCandidate(uint index) external onlyOwner {
        WorkerCandidate memory candidate = candidates[index]; 

        require(index < candidates.length, "out of bounds");   
        require(candidate.proposedTime.add(approvalDelay) < now, "!delay");

        workers.push(candidate.addr); 
        IERC20(want).safeApprove(candidate.addr, uint(-1));
        _removeCandidate(index);

        emit CandidateAccepted(candidate.addr);
    }

    /**
     * @dev Cancels an attempt to add a worker. Useful in case of an erronoeus proposal,
     * or a bug found later in an upcoming candidate.
     * @param index Index of candidate in the {candidates} array.
     */
    function rejectCandidate(uint index) external onlyOwner {
        emit CandidateRejected(candidates[index].addr);

        _removeCandidate(index);
    }   

    /** 
     * @dev Internal function to remove a candidate from the {candidates} array.
     * @param index Index of candidate in the {candidates} array.
    */
    function _removeCandidate(uint index) internal {
        candidates[index] = candidates[candidates.length-1];
        candidates.pop();
    } 

    //--- WORKER MANAGEMENT ---//

    /**
     * @dev Function to set any worker as the main one. The worker at index 0 has that role. 
     * User deposits go there and withdraws try to take out from there first. 
     * @param index Index of worker to promote.
     */ 
    function setMainWorker(uint index) external onlyOwner {
        require(index != 0, "!main");
        require(index < workers.length, "out of bounds");   

        address temp = workers[0];
        workers[0] = workers[index];
        workers[index] = temp;
    }

    /**
     * @dev Withdraws all {want} from a worker and removes it from the options. 
     * Can't be called with the main worker, at index 0.
     * @param index Index of worker in the {workers} array.
     */
    function deleteWorker(uint index) external onlyOwner {
        require(index != 0, "!main");
        require(index < workers.length, "out of bounds");   

        emit WorkerDeleted(workers[index]);
        IERC20(want).safeApprove(workers[index], 0);

        _workerWithdraw(index);
        _removeWorker(index);

        deposit();
    }

    /** 
     * @dev Internal function to remove a worker from the {workers} array.
     * @param index Index of worker in the {workers} array.
    */
    function _removeWorker(uint index) internal {
        workers[index] = workers[workers.length-1];
        workers.pop();
    } 

    //--- FUND MANAGEMENT HELPERS ---//

    /**
     * @dev Function to give or remove {want} allowance from workers.
     * @param amount Allowance to set. Either '0' or 'uint(-1)' 
     */
    function _workerApproveAll(uint amount) internal {
        for (uint8 i = 0; i < workers.length; i++) {
            IERC20(want).approve(workers[i], amount);
        }
    }

    /**
     * @dev Deposits all {want} in the contract into the given worker.
     * @param workerIndex Index of the worker where the funds will go.
     */
    function _workerDeposit(uint workerIndex) internal {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IVault(workers[workerIndex]).deposit(wantBal);
    }

    /**
     * @dev Withdraws all {want} from all workers.
     */
    function _workersWithdrawAll() internal {
        for (uint8 i = 0; i < workers.length; i++) {
            _workerWithdraw(i);
        }
    }

    /** 
     * @dev Internal function to withdraw all {want} from a particular worker.
     * @param workerIndex Index of the worker to withdraw from.
    */
    function _workerWithdraw(uint workerIndex) internal {
        require(workerIndex < workers.length, "out of bounds");   

        address worker = workers[workerIndex];
        uint256 shares = IERC20(worker).balanceOf(address(this));

        IERC20(worker).approve(worker, shares);
        IVault(worker).withdraw(shares);
    }

    /** 
     * @dev Internal function to withdraw some {want} from a particular worker.
     * @param workerIndex Index of the worker to withdraw from.
     * @param amount How much {want} to withdraw.
    */
    function _workerPartialWithdraw(uint workerIndex, uint amount) internal {
        require(workerIndex < workers.length, "out of bounds");   

        address worker = workers[workerIndex];
        uint256 pricePerFullShare = IVault(worker).getPricePerFullShare();
        uint256 shares = amount.mul(1e18).div(pricePerFullShare);

        IERC20(worker).approve(worker, shares);
        IVault(worker).withdraw(shares);
    }

    //--- STRATEGY LIFECYCLE METHODS ---//

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the 
     * vault, ready to be migrated to the new strat.
     */ 
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

       _workersWithdrawAll();

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from workers.
     */
    function panic() external onlyOwner {        
        _workersWithdrawAll();
        pause();
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public onlyOwner {
        _pause();
        _workerApproveAll(0);
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external onlyOwner {
        _unpause();
        _workerApproveAll(uint(0));
    }

    //--- VIEW FUNCTIONS ---//

    /**
     * @dev Function to calculate the total underlaying {want} held by the strat.
     * It takes into account both funds at hand, as funds allocated in every worker.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfWorkers());
    }

    /**
     * @dev It calculates how much {want} the contract holds.
     */
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /**
     * @dev It calculates the total {want} locked in all workers.
     */
    function balanceOfWorkers() public view returns (uint256) {
        uint totalBal = 0;

        for (uint8 i = 0; i < workers.length; i++) {
            totalBal = totalBal.add(_workerBalance(i));
        }

        return totalBal;
    }

    /**
     * @dev How much {want} a balancer holds in a particular worker.
     * @param workerIndex Index of the worker to withdraw from.
     */
    function _workerBalance(uint workerIndex) internal view {
        uint shares = IERC20(workers[workerIndex]).balanceOf(address(this));  
        uint pricePerShare = IVault(workers[workerIndex]).getPricePerFullShare();
        return shares.mul(pricePerShare).div(1e18);
    }
}