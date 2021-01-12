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
 * - addWorker should be timelocked.
 * Constrains:
 * - Can only be used with new vaults or balanceOfVaults breaks.
 * - Vaults that serve as workers can't charge withdraw fee to make it work.
 */
contract YieldBalancer is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /**
     * @dev Worker management structs.
     */
    struct WorkerCandidate {
        address addr;
        uint proposedTime;
        bool accepted;
        bool processed;
    }

    address public want;
    address public vault;
    address[] public workers;

    /**
     * @notice Initializes the strategy
     * @param _want Address of the token to maximize.
     * @param _vault Address of the vault that will manage the strat.
     * @param _workers Array of vault addresses that will serve as workers.
     */
    constructor(address _want, address _vault, address[] memory _workers) public {
        want = _want;
        vault = _vault;
        workers = _workers;

        _wantApproveAll(uint(-1));
    }

    /**
     * @dev Function to give or remove want allowance from workers.
     */
    function _wantApproveAll(uint amount) internal {
        for (uint8 i = 0; i < workers.length; i++) {
            IERC20(want).approve(workers[i], amount);
        }
    }

    /**
     * @dev Function that puts the funds to work.
     */
    function deposit() public {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        for (uint8 i = 0; i < subvaults.length; i++) {
            Vault memory vault = subvaults[i]; 
            uint256 depositAmount = wantBal.mul(vault.currentAlloc).div(100);
            IVault(vault).deposit(depositAmount);
        }
    }

    /**
     * @dev It withdraws {want} from the workers and sends it to the vault.
     */
    function withdraw(uint256 _amount) public {
        require(msg.sender == vault, "!vault");

        for (uint8 i = 0; i < subvaults.length; i++) {
            Vault memory _vault = subvaults[i]; 
            uint256 vaultAmount = _amount.mul(_vault.currentAlloc).div(100);
            uint256 pricePerFullShare = IVault(_vault).getPricePerFullShare();
            uint256 shares = vaultAmount.mul(1e18).div(pricePerFullShare);

            IERC20(_vault).approve(_vault, shares);
            IVault(vault).withdraw(shares);
        }

        IERC20(want).safeTransfer(vault, _amount);
    }

    /**
     * @dev Function that has to be called as part of strat migration. It sends all the available funds back to the 
     * vault, ready to be migrated to the new strat.
     */ 
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        for (uint8 i = 0; i < subvaults.length; i++) {
            Vault memory _vault = subvaults[i]; 

            uint256 shares = IERC20(_vault).balanceOf(address(this));
            IERC20(_vault).approve(_vault, shares);
            IVault(_vault).withdraw(shares);

            IERC20(want).approve(_vault, uint256(0));
        }

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);

         _pause();
    }

    /**
     * @dev Pauses deposits. Withdraws all funds from the different vaults.
     */
    function panic() public onlyOwner {        
        for (uint8 i = 0; i < subvaults.length; i++) {
            Vault memory _vault = subvaults[i]; 

            uint256 shares = IERC20(_vault).balanceOf(address(this));
            IERC20(_vault).approve(_vault, shares);
            IVault(vault).withdraw(shares);
        }

        pause();
    }

    function proposeCandidate() public onlyOwner {

    }

    function rejectCandidate() public onlyOwner {

    }

    function acceptCandidate() public onlyOwner {

    }

    function deleteWorker() public onlyOwner {

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