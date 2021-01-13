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
 *   
 * To-Do:
 * - Add the rebalance helper functions.
 * - Be able to make a worker the main worker.
 * - Add more events that the bot can listen to.
 * Constrains:
 * - Can only be used with new vaults or balanceOfVaults breaks.
 * - subvaults that serve as workers can't charge withdraw fee to make it work.
 */
contract YieldBalancer is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public want;
    address public vault;

    /**
     * @dev Worker management structs.
     */
    struct WorkerCandidate {
        address addr;
        uint proposedTime;
    }

    /**
     * @dev Worker management variables.
     */
    WorkerCandidate[] public candidates;
    address[] public workers;

    /**
     * @dev Used to protect vault users against vault hoping.
     * {WITHDRAWAL_FEE} - Fee taxed when a user withdraws funds. 10 === 0.1% fee.
     * {WITHDRAWAL_MAX} - Aux const used to safely calc the correct amounts.
     */
    uint constant public WITHDRAWAL_FEE = 10;
    uint constant public WITHDRAWAL_MAX = 10000;

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

        _wantApproveAll(uint(-1));
    }

    /**
     * @dev Function that puts the funds to work.
     */
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        IVault(workers[0]).deposit(wantBal);
    }

    /**
     * @dev It withdraws {want} from the workers and sends it to the vault.
     * @param amount how much {want} to withdraw.
     */
    function withdraw(uint amount) public {
        require(msg.sender == vault, "!vault");

        uint wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < amount) {
            for (uint8 i = 0; i < workers.length; i++) {
                address worker = workers[i];
                uint workerBal = IVault(worker).balance();
                if (workerBal < amount.sub(wantBal)) {
                    _withdrawWorker(worker);
                    wantBal = IERC20(want).balanceOf(address(this));
                } else {
                    _withdrawWorkerPartial(worker, amount.sub(wantBal));
                    break;
                }
            }
        }

        wantBal = IERC20(want).balanceOf(address(this));
        uint _fee = wantBal.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
        IERC20(want).safeTransfer(vault, wantBal.sub(_fee));
    }

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
     * @dev Cancels an attempt to add a worker. Useful in case of a mistake
     * @param index Index of candidate in the {candidates} array.
     */
    function rejectCandidate(uint index) external onlyOwner {
        emit CandidateRejected(candidates[index]);

        _removeCandidate(index);
    }   

    /**
     * @dev Adds a candidate to the worker pool. Can only be done after {approvalDelay} has passed.
     * @param index Index of candidate in the {candidates} array.
     */
    function acceptCandidate(uint index) external onlyOwner {
        memory candidate = WorkerCandidate(candidates[index]); 

        require(index < candidates.length, "out of bounds");   
        require(candidate.proposedTime.add(approvalDelay) < now, "!delay");

        workers.push(candidate.addr); 
        IERC20(want).safeApprove(candidate.addr, uint(-1));
        _removeCandidate(index);

        emit CandidateAccepted(candidate.addr);
    }

    /**
     * @dev Withdraws all {want} from a worker and removes it from the options. 
     * Can't be called with the main worker, at index 0.
     * @param index Index of worker in the {workers} array.
     */
    function deleteWorker(uint index) external onlyOwner {
        require(index != 0, "!main");
        require(index < workers.length, "out of bounds");   

        address worker = workers[index];

        _withdrawWorker(worker);
        _removeWorker(index);

        IERC20(want).safeApprove(candidate.addr, uint(-1));

        deposit();

        emit WorkerDeleted(worker);
    }

    /** 
     * @dev Internal function to remove a worker from the {workers} array.
     * @param index Index of worker in the {workers} array.
    */
    function _removeWorker(uint index) internal {
        workers[index] = workers[workers.length-1];
        delete workers[workers.length-1];
        workers.length--;
    } 

    /** 
     * @dev Internal function to remove a candidate from the {candidates} array.
     * @param index Index of candidate in the {candidates} array.
    */
    function _removeCandidate(uint index) internal {
        candidates[index] = candidates[candidates.length-1];
        delete candidates[candidates.length-1];
        candidates.length--;
    } 

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the 
     * vault, ready to be migrated to the new strat.
     */ 
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
       _withdrawAll();

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from workers.
     */
    function panic() public onlyOwner {        
        _withdrawAll();
        pause();
    }

    /**
     * @dev Withdraws all {want} from all workers.
     */
    function _withdrawAll() internal {
        for (uint8 i = 0; i < workers.length; i++) {
            address worker = workers[i];
            _withdrawWorker(worker);
        }
    }

    /** 
     * @dev Internal function to withdraw all {want} from a particular worker.
     * @param worker Address of the worker to withdraw from.
    */
    function _withdrawWorker(address worker) internal {
        // TODO: What happens if this is not one of our actual workers...?
        uint256 shares = IERC20(worker).balanceOf(address(this));
        IERC20(worker).approve(worker, shares);
        IVault(worker).withdraw(shares);
    }

    /** 
     * @dev Internal function to withdraw some {want} from a particular worker.
     * @param worker Address of the worker to withdraw from.
     * @param amount How much {want} to withdraw.
    */
    function _withdrawWorkerPartial(address worker, uint amount) internal {
        uint256 pricePerFullShare = IVault(worker).getPricePerFullShare();
        uint256 shares = amount.mul(1e18).div(pricePerFullShare);

        IERC20(worker).approve(worker, shares);
        IVault(worker).withdraw(shares);
    }

    /**
     * @dev Function to give or remove {want} allowance from workers.
     * @param amount Allowance to set. Either '0' or 'uint(-1)' 
     */
    function _wantApproveAll(uint amount) internal {
        for (uint8 i = 0; i < workers.length; i++) {
            IERC20(want).approve(workers[i], amount);
        }
    }

    /**
     * @dev Pauses the strat.
     */
    function pause() public onlyOwner {
        _pause();
        _wantApproveAll(0);
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause() external onlyOwner {
        _unpause();
        _wantApproveAll(uint(0));
    }

    /**
     * @dev Function to calculate the total underlaying {want} held by the strat.
     * It takes into account both funds at hand, as funds allocated in every worker.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfVaults());
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
    function balanceOfVaults() public view returns (uint256) {
        uint256 _balance = 0;

        for (uint8 i = 0; i < workers.length; i++) {
            _balance = _balance.add(IVault(workers[i]).balance());
        }

        return _balance;
    }
}