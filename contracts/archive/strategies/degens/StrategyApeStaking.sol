// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../../utils/UniswapV3Utils.sol";

interface IApeStaking {
    function depositSelfApeCoin(uint256 _amount) external;
    function withdrawSelfApeCoin(uint256 _amount) external;
    function claimSelfApeCoin() external;
    function getApeCoinStake(address _address) external view returns (uint poolId, uint tokenId, uint deposited, uint unclaimed);
}

contract StrategyApeStaking is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public constant want = 0x4d224452801ACEd8B2F0aebE155379bb5D594381;
    address public constant native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Third party contracts
    address public constant unirouterV3 = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    IApeStaking public chef;

    // uniswap v3 path
    bytes public wantToNativePath;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(address _staking, CommonAddresses calldata _commonAddresses) public initializer {
        __StratFeeManager_init(_commonAddresses);
        chef = IApeStaking(_staking);
        wantToNativePath  = hex'4d224452801aced8b2f0aebe155379bb5d594381000bb8c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
        harvestOnDeposit = true;
        setWithdrawalFee(0);
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            chef.depositSelfApeCoin(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            _withdraw(_amount - wantBal);
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal * withdrawalFee / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function _withdraw(uint256 _amount) internal {
        chef.withdrawSelfApeCoin(_amount);
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin, true);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin, false);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient, false);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient, bool onDeposit) internal whenNotPaused {
        chef.claimSelfApeCoin();
        uint256 wantBal = balanceOfWant();
        if (wantBal > 0) {
            chargeFees(callFeeRecipient);
            uint256 wantHarvested = balanceOfWant();
            if (!onDeposit) {
                deposit();
            }

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 toNative = balanceOfWant() * fees.total / DIVISOR;
        UniswapV3Utils.swap(unirouter, wantToNativePath, toNative);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (,,uint amount,) = chef.getApeCoinStake(address(this));
        return amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        (,,,uint unclaimed) = chef.getApeCoinStake(address(this));
        return unclaimed;
    }

    // native reward amount for calling harvest
    function callReward() public pure returns (uint256) {
        return 0;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        if (balanceOfPool() > 1) {
            _withdraw(balanceOfPool());
        }

        uint wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        _withdraw(balanceOfPool());
    }

    // pauses deposits and withdraws all funds-1 to avoid claim rewards
    function panicWithoutClaim() public onlyManager {
        pause();
        _withdraw(balanceOfPool() - 1);
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        uint amount = type(uint).max;
        _approve(want, address(chef), amount);
        _approve(want, unirouter, amount);
    }

    function _removeAllowances() internal {
        _approve(want, address(chef), 0);
        _approve(want, unirouter, 0);
    }

    function _approve(address _token, address _spender, uint amount) internal {
        IERC20(_token).approve(_spender, amount);
    }

    function setWantToNativePath(bytes calldata _wantToNativePath) public onlyOwner {
        wantToNativePath = _wantToNativePath;
    }
}