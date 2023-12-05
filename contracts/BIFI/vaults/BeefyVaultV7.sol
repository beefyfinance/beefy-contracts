// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/beefy/IStrategyV7.sol";

/**
 * @dev Implementation of a vault to deposit funds for yield optimizing.
 */
contract BeefyVaultV7 is ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct StratCandidate {
        address implementation;
        uint proposedTime;
    }

    StratCandidate public stratCandidate;
    IStrategyV7 public strategy;
    uint256 public approvalDelay;

    event NewStratCandidate(address implementation);
    event UpgradeStrat(address implementation);

    function initialize(
        IStrategyV7 _strategy,
        string memory _name,
        string memory _symbol,
        uint256 _approvalDelay
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __Ownable_init();
        __ReentrancyGuard_init();
        strategy = _strategy;
        approvalDelay = _approvalDelay;
    }

    function want() public view returns (IERC20Upgradeable) {
        return IERC20Upgradeable(strategy.want());
    }

    function balance() public view returns (uint) {
        return want().balanceOf(address(this)) + strategy.balanceOf();
    }

    function available() public view returns (uint256) {
        return want().balanceOf(address(this));
    }

    function getPricePerFullShare() public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        return _totalSupply == 0 ? 1e18 : balance() * 1e18 / _totalSupply;
    }

    function depositAll() external {
        deposit(want().balanceOf(msg.sender));
    }

    function deposit(uint _amount) public nonReentrant {
        strategy.beforeDeposit();

        uint256 _pool = balance();
        want().safeTransferFrom(msg.sender, address(this), _amount);
        earn();
        uint256 _after = balance();
        _amount = _after - _pool; // Adjust for deflationary tokens
        uint256 shares = totalSupply() == 0 ? _amount : (_amount * totalSupply()) / _pool;
        _mint(msg.sender, shares);
    }

    function earn() public {
        uint _bal = available();
        want().safeTransfer(address(strategy), _bal);
        strategy.deposit();
    }

    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    function withdraw(uint256 _shares) public nonReentrant {
        uint256 r = (balance() * _shares) / totalSupply();
        _burn(msg.sender, _shares);

        uint b = want().balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r - b;
            strategy.withdraw(_withdraw);
            uint _after = want().balanceOf(address(this));
            r = _after < _withdraw ? b + (_after - b) : r;
        }

        want().safeTransfer(msg.sender, r);
    }

    function proposeStrat(address _implementation) public onlyOwner {
        require(address(this) == IStrategyV7(_implementation).vault(), "Invalid vault");
        require(want() == IStrategyV7(_implementation).want(), "Different want");
        stratCandidate = StratCandidate({
            implementation: _implementation,
            proposedTime: block.timestamp
         });

        emit NewStratCandidate(_implementation);
    }

    function upgradeStrat() public onlyOwner {
        require(stratCandidate.implementation != address(0), "No candidate");
        require(block.timestamp >= stratCandidate.proposedTime + approvalDelay, "Delay not passed");

        emit UpgradeStrat(stratCandidate.implementation);

        strategy.retireStrat();
        strategy = IStrategyV7(stratCandidate.implementation);
        stratCandidate.implementation = address(0);
        stratCandidate.proposedTime = 5000000000;

        earn();
    }

    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want()), "Cannot withdraw want token");

        uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(msg.sender, amount);
    }
}
