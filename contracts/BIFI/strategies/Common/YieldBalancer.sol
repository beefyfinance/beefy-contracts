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
 * - Add withdraw fee
 * Constrains:
 * - Can only be used with new vaults or balanceOfVaults breaks.
 * - Vaults that serve as workers can't charge withdraw fee to make it work.
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
        IERC20(want).safeTransfer(vault, wantBal);
    }

    /**
     * @dev Starts the process to add a new worker.
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
     */
    function rejectCandidate(uint index) external onlyOwner {
        emit CandidateRejected(candidates[index]);

        _removeCandidate(index);
    }   

    /**
     * @dev 
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
     * @dev 
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

    function _removeWorker(uint index) internal {
        workers[index] = workers[workers.length-1];
        delete workers[workers.length-1];
        workers.length--;
    } 

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
     * @dev Withdraws all {want} from workers.
     */
    function _withdrawAll() internal {
        for (uint8 i = 0; i < workers.length; i++) {
            address worker = workers[i];
            _withdrawWorker(worker);
        }
    }

    function _withdrawWorker(address worker) internal {
        uint256 shares = IERC20(worker).balanceOf(address(this));
        IERC20(worker).approve(worker, shares);
        IVault(worker).withdraw(shares);
    }

    /** 
     * @dev 
    */
    function _withdrawWorkerPartial(address worker, uint amount) {
        uint256 pricePerFullShare = IVault(worker).getPricePerFullShare();
        uint256 shares = amount.mul(1e18).div(pricePerFullShare);

        IERC20(worker).approve(worker, shares);
        IVault(worker).withdraw(shares);
    }

    /**
     * @dev Function to give or remove {want} allowance from workers.
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