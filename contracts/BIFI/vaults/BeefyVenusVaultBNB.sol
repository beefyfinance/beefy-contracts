// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/beefy/IVenusStrategyBNB.sol";
import "../interfaces/common/IWBNB.sol";

/**
 * @title BeefyVault BNB
 * @author sirbeefalot & superbeefyboy
 * @dev Implementation of a custom vault to deposit exclusively BNB and WBNB on 
 * the Venus lending platform for yield optimizing.
 * This is the contract that receives funds and that users interface with.
 * The yield optimizing strategy itself is implemented in a separate contract.
 */
contract BeefyVenusVaultBNB is ERC20, Ownable {
    using SafeERC20 for IWBNB;
    using Address for address;
    using SafeMath for uint256;

    struct StratCandidate {
        address implementation;
        uint proposedTime;
    }

    // The last proposed strategy to switch to.
    StratCandidate public stratCandidate; 
    // The strategy currently in use by the vault.
    address public strategy;
    // BEP20 token version of BNB.
    IWBNB constant public wbnb = IWBNB(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    // The minimum time it has to pass before a strat candidate can be approved.
    uint256 public immutable approvalDelay;

    event NewStratCandidate(address implementation);
    event UpgradeStrat(address implementation);
    
    /**
     * @dev It initializes the vault's own 'moo' token.
     * This token acts as vault 'shares'. It's minted when someone deposits and it's 
     * burned in order to withdraw the corresponding portion of the underlying BNB.
     * @param _strategy the address of the strategy.
     * @param _name the name of the vault token.
     * @param _symbol the symbol of the vault token.
     * @param _approvalDelay the delay before a new strat can be approved.
     */
    constructor (
        address _strategy, 
        string memory _name, 
        string memory _symbol, 
        uint256 _approvalDelay
    ) public ERC20(
        string(_name),
        string(_symbol)
    ) {
        strategy = _strategy;
        approvalDelay = _approvalDelay;
    }

    /**
     * @dev It calculates the total underlying value of {wbnb} held by the system.
     * It takes into account the vault contract balance, the strategy contract balance
     * and the balance deployed in other contracts as part of the strategy.
     */
    function balance() public view returns (uint256) {
        return available().add(IVenusStrategyBNB(strategy).balanceOf());
    }

    /**
     * @dev Custom logic in here for how much the vault allows to be borrowed.
     * We return 100% of tokens for now. Under certain conditions we might
     * want to keep some of the system funds at hand in the vault, instead
     * of putting them to work.
     */
    function available() public view returns (uint256) {
        return wbnb.balanceOf(address(this));
    }

    /**
     * @dev Function for various UIs to display the current value of one of our yield tokens.
     * Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
     */
    function getPricePerFullShare() public view returns (uint256) {
        return balance().mul(1e18).div(totalSupply());
    }

    /**
     * @dev A helper function to call deposit() with all the sender's funds.
     */
    function depositAll() external {
        deposit(wbnb.balanceOf(msg.sender));
    }

    /**
     * @dev The entry point of funds into the system. People deposit with this function
     * into the vault. The vault is then in charge of sending funds into the strategy.
     */
    function deposit(uint _amount) public {
        IVenusStrategyBNB(strategy).updateBalance();

        uint256 _pool = balance();
        wbnb.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);

        earn();
    }

    /**
     * @dev Alternative entry point into the strat. You can send native BNB,
     * and the vault will wrap them before sending them into the strat.
     */
    function depositBNB() public payable {
        IVenusStrategyBNB(strategy).updateBalance();

        uint256 _pool = balance();
        uint256 _before = wbnb.balanceOf(address(this));
        uint256 _amount = msg.value;
        wbnb.deposit{value: _amount}();
        
        uint256 _after = wbnb.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);

        earn();
    }

    /**
     * @dev Function to send funds into the strategy and put them to work. It's primarily called
     * by the vault's deposit() function.
     */
    function earn() public {
        uint _bal = available();
        wbnb.safeTransfer(strategy, _bal);
        IVenusStrategyBNB(strategy).deposit();
    }

    /**
     * @dev A helper function to call withdraw() with all the sender's funds.
     */
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }
    
    /**
     * @dev Alternative helper function to withdraw all funds in native bnb form.
     */
    function withdrawAllBNB() external {
        withdrawBNB(balanceOf(msg.sender));
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     */
    function withdraw(uint256 _shares) public {
        IVenusStrategyBNB(strategy).updateBalance();

        uint256 r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        uint256 b = wbnb.balanceOf(address(this));
        if (b < r) {
            uint256 _withdraw = r.sub(b);
            IVenusStrategyBNB(strategy).withdraw(_withdraw);
            uint256 _after = wbnb.balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        wbnb.safeTransfer(msg.sender, r);
    }

    /**
     * @dev Alternative function to exit the system. Works just like 'withdraw(uint256)',
     * but the funds arrive in native bnb.
     */
    function withdrawBNB(uint256 _shares) public {
        IVenusStrategyBNB(strategy).updateBalance();

        uint256 r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        uint256 b = wbnb.balanceOf(address(this));
        if (b < r) {
            uint256 _withdraw = r.sub(b);
            IVenusStrategyBNB(strategy).withdraw(_withdraw);
            uint256 _after = wbnb.balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        wbnb.withdraw(r);
        msg.sender.transfer(r);
    }

    /** 
     * @dev Sets the candidate for the new strat to use with this vault.
     * @param _implementation The address of the candidate strategy.  
     */
    function proposeStrat(address _implementation) public onlyOwner {
        stratCandidate = StratCandidate({ 
            implementation: _implementation,
            proposedTime: block.timestamp
         });

        emit NewStratCandidate(_implementation);
    }

    /** 
     * @dev It switches the active strat for the strat candidate. You have to call 'retireStrat'
     * in the strategy contract before. This pauses the old strat and makes sure that all the old 
     * strategy funds are sent back to this vault before switching strats. When upgrading, the 
     * candidate implementation is set to the 0x00 address, and proposedTime to a time happening in +100 years for safety. 
     */

    function upgradeStrat() public onlyOwner {
        require(stratCandidate.implementation != address(0), "There is no candidate");
        require(stratCandidate.proposedTime.add(approvalDelay) < block.timestamp, "Delay has not passed");
        
        emit UpgradeStrat(stratCandidate.implementation);

        IVenusStrategyBNB(strategy).retireStrat();
        strategy = stratCandidate.implementation;
        stratCandidate.implementation = address(0);
        stratCandidate.proposedTime = 5000000000;
        
        earn();
    }

    receive () external payable {}
}