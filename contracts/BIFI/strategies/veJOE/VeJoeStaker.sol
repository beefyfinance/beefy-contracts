// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./IVeJoe.sol";
import "./GaugeManager.sol";

interface IERC1271 {
    function isValidSignature(
        bytes32 hash,
        bytes signature
    ) external returns (bytes4 magicValue);
}

contract VeJoeStaker is ERC20Upgradeable, IERC1271, ReentrancyGuardUpgradeable, GaugeManager {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    // Tokens used
    IERC20Upgradeable public want;
    IVeJoe public veWant;
    IJoeChef public joeChef;

    uint256 public max = 1000;
    uint256 public reserveRate = 800; 

    event DepositWant(uint256 tvl);
    event Withdraw(uint26 tvl);
    event RecoverTokens(address token, uint256 amount);

    function initialize(
        address _veWant,
        address _keeper,
        address _rewardPool,
        address _joeChef,
        string memory _name,
        string memory _symbol
    ) public initializer {
        managerInitialize(_keeper, _rewardPool);
        veWant = IVeWant(_veWant);
        want = IERC20Upgradeable(veWant.token());
        joeChef = IJoeChef(_joeChef);

        __ERC20_init(_name, _symbol);

        want.safeApprove(address(veWant), type(uint256).max);
    }

    // helper function for depositing full balance of want
    function depositAll() external {
        _deposit(msg.sender, want.balanceOf(msg.sender));
    }

    // deposit an amount of want
    function deposit(uint256 _amount) external {
        _deposit(msg.sender, _amount);
    }

    // deposit an amount of want on behalf of an address
    function depositFor(address _user, uint256 _amount) external {
        _deposit(_user, _amount);
    }

    // deposit 'want' and lock
    function _deposit(address _user, uint256 _amount) internal nonReentrant whenNotPaused {
        harvestAndDepositJoe();
        uint256 _pool = balanceOfWant();
        want.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = balanceOfWant();
        _amount = _after.sub(_pool); // Additional check for deflationary tokens

        if (_amount > 0) {
            _mint(_user, _amount);
            emit DepositWant(balanceOfVe());
        }
    }

    function withdraw(uint256 _amount) public {
        require(_amount > balanceOfWant(), "Not enough Joes to withdraw");
        _burn(msg.sender, _amounts);
        want().safeTransfer(msg.sender, _amount);
    }

    function harvestAndDepositJoe() public { 
        if (totalJoes() > 0) {
            if (balanceOfWant() > requiredReserve()) {
                uint256 avaialableBalance = balanceOfWant().sub(requiredReserve());
                // we want the bonus for depositing more than 5% of our already deposited joes
                uint256 joesNeededForBonus = balanceOfJoeInVe().mul(veJoe.speedUpThreshold()).div(100);
                if (avaialableBalance > joesNeededForBonus) {
                    veJoe.deposit(avaialableBalance);
                } 
            }
            harvestVeJoe();
        }
    }

    // claim the veJoes
    function harvestVeJoe() public {
        veJoe.claim();
    }

    function requiredReserve() public view returns (uint256 reqReserve) {
        // We calculate allocation for 20% or the total supply of contract to the reserve.
        reqReserve = totalJoes().mul(reserveRate).div(max);
    }

    function totalJoes() public view returns (uint256) {
        return balanceOfWant().add(balanceOfJoeInVe());
    }

    // calculate how much 'want' is held by this contract
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // calculate how much 'veWant' is held by this contract
    function balanceOfVe() public view returns (uint256) {
        return veWant.balanceOf(address(this));
    }

    // how many joes we got earning ve? 
    function balanceOfJoeInVe() public view returns (uint256 joes) {
        (joes,,,) = veWant.userInfos(address(this));
    }

    // prevent any further 'want' deposits and remove approval
    function pause() public onlyManager {
        _pause();
        want.safeApprove(address(veWant), 0);
    }

    // allow 'want' deposits again and reinstate approval
    function unpause() external onlyManager {
        _unpause();
        want.safeApprove(address(veWant), type(uint256).max);
        uint256 reserveAmt = balanceOfWant().mul(reserveRate).div(max);
        veJoe.deposit(balanceOfWant().sub(reserveAmt));
    }

    // panic the veJoe losing all accrued veJOE 
    function panic() external onlyManager {
        pause();
        veJoe.withdraw(balanceOfJoeInVe);
    }

    // pass through a deposit to a gauge
    function deposit(uint256 _pid, uint256 _amount) external onlyWhitelist(_pid) {
        address _underlying = IGauge(_gauge).TOKEN();
        IERC20Upgradeable(_underlying).safeTransferFrom(msg.sender, address(this), _amount);
        IGauge(_gauge).deposit(_amount);
    }

    // pass through a withdrawal from a gauge
    function withdraw(address _gauge, uint256 _amount) external onlyWhitelist(_pid) {
        address _underlying = IGauge(_gauge).TOKEN();
        IGauge(_gauge).withdraw(_amount);
        IERC20Upgradeable(_underlying).safeTransfer(msg.sender, _amount);
    }

    // pass through a full withdrawal from a gauge
    function withdrawAll(address _gauge) external onlyWhitelist(_pid) {
        address _underlying = IGauge(_gauge).TOKEN();
        uint256 _before = IERC20Upgradeable(_underlying).balanceOf(address(this));
        IGauge(_gauge).withdrawAll();
        uint256 _balance = IERC20Upgradeable(_underlying).balanceOf(address(this)).sub(_before);
        IERC20Upgradeable(_underlying).safeTransfer(msg.sender, _balance);
    }

    // pass through rewards from a gauge
    function claimGaugeReward(address _gauge) external onlyWhitelist(_pid) {
        uint256 _before = balanceOfWant();
        IGauge(_gauge).getReward();
        uint256 _balance = balanceOfWant().sub(_before);
        want.safeTransfer(msg.sender, _balance);
    }

    // recover any unknown tokens
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want), "!token");

        uint256 _amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(msg.sender, _amount);

        emit RecoverTokens(_token, _amount);
    }

    /**
    * @notice Verifies that the signer is the owner of the signing contract.
    */
    function isValidSignature(
        bytes32 _hash,
        bytes calldata _signature
    ) external override view returns (bytes4) {
        // Validate signatures
        if (recoverSigner(_hash, _signature) == keeper) {
            return 0x1626ba7e;
        } else {
            return 0xffffffff;
    }   
  }
}
