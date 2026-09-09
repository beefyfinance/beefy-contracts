// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/infra/BeefyFeeConfigurator.sol";
import "../../../contracts/BIFI/strategies/Common/BaseAllToNativeStrat.sol";
import "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";

/// @title BaseAllToNativeStrat: only harvested profit should be locked
/// @notice Regression tests for the harvest accounting of BaseAllToNativeStrat.
///
/// The legacy base computes `wantHarvested = balanceOfWant()` (the full want
/// balance) and locks it as profit. BaseAllToNativeFactoryStrat (the newer
/// base) snapshots the balance before the harvest and locks only the delta.
/// These tests assert the delta behavior: idle want (donations, withdrawal-fee
/// residue, rounding dust) must not be locked as profit, while the intended
/// profit smoothing over `lockDuration` is preserved.
contract BaseAllToNativeLockedProfitTest is Test {
    MockERC20 want;
    MockERC20 native;
    BeefyFeeConfigurator feeConfig;
    BeefyVaultV7 vault;
    MockSwapper swapper;
    MockPool pool;
    MockStrategy strat;

    address alice = address(0xA11CE);
    address attacker = address(0xA77);
    uint256 constant PROFIT = 10e18;
    uint256 constant DONATION = 100e18;
    uint256 constant ATTACK_DEPOSIT = 2000e18;

    function setUp() public {
        want = new MockERC20("Want", "WANT");
        native = new MockERC20("Native", "NAT");
        swapper = new MockSwapper();
        pool = new MockPool();

        // zero-fee default category keeps the profit math clean
        feeConfig = new BeefyFeeConfigurator();
        feeConfig.initialize(address(this), 20e16);
        feeConfig.setFeeCategory(0, 0, 0, 0, "default", true, false);

        vault = new BeefyVaultV7();

        StratFeeManagerInitializable.CommonAddresses memory common = StratFeeManagerInitializable.CommonAddresses({
            vault: address(vault),
            unirouter: address(swapper),
            keeper: address(this),
            strategist: address(this),
            beefyFeeRecipient: address(this),
            beefyFeeConfig: address(feeConfig)
        });

        strat = new MockStrategy();
        strat.init(address(want), address(native), pool, new address[](0), common);

        vault.initialize(IStrategyV7(address(strat)), "moo Want", "mooWANT", 2 weeks);

        // swapper settles native -> want 1:1
        want.mint(address(swapper), 1_000_000e18);
        vm.prank(address(strat));
        native.approve(address(swapper), type(uint256).max);

        // Alice seeds the vault: 1000 want -> 1000 shares, PPS = 1.0
        want.mint(alice, 1000e18);
        vm.startPrank(alice);
        want.approve(address(vault), type(uint256).max);
        vault.deposit(1000e18);
        vm.stopPrank();

        vm.warp(1 days); // nonzero clock so lock accounting is meaningful
    }

    /// @dev donates `donation` of want to the strategy, earns `profit` (native),
    ///      then harvests. Returns totalLocked after the harvest.
    function _harvestWith(uint256 donation, uint256 profit) internal returns (uint256) {
        if (donation > 0) want.mint(address(strat), donation);
        native.mint(address(strat), profit);
        strat.harvest();
        return strat.totalLocked();
    }

    /// @dev idle want present at harvest time must not be locked as profit:
    ///      only the 10e18 actually harvested is locked, the 100e18 donation
    ///      stays liquid. Fails if wantHarvested = balanceOfWant() (full balance).
    function test_OnlyHarvestedProfitIsLocked() public {
        uint256 locked = _harvestWith(DONATION, PROFIT);
        assertEq(locked, PROFIT, "totalLocked must equal harvested delta only");
    }

    /// @dev the donation must be reflected in PPS immediately (not delayed by
    ///      the lock window). Old behavior understates PPS by the idle amount.
    function test_IdleWantReflectedInPpsImmediately() public {
        _harvestWith(DONATION, PROFIT);
        uint256 ppsDuringLock = vault.balance() * 1e18 / vault.totalSupply();
        vm.warp(block.timestamp + 1 days + 1 seconds);
        uint256 ppsAfterLock = vault.balance() * 1e18 / vault.totalSupply();

        // with delta locking: during lock PPS = (1110 - 10) / 1000 = 1.1
        assertEq(ppsDuringLock, 1.1e18, "idle want must count toward PPS during lock");
        assertEq(ppsAfterLock, 1.11e18, "PPS after lock = principal + donation + profit");
    }

    /// @dev the intended smoothing of harvested profit is preserved:
    ///      PPS is understated by the locked profit during the window.
    function test_ProfitSmoothingPreserved() public {
        _harvestWith(0, PROFIT);
        uint256 ppsDuringLock = vault.balance() * 1e18 / vault.totalSupply();
        vm.warp(block.timestamp + 1 days + 1 seconds);
        uint256 ppsAfterLock = vault.balance() * 1e18 / vault.totalSupply();

        assertLt(ppsDuringLock, ppsAfterLock, "profit smoothing must still understate PPS");
        assertEq(ppsDuringLock, 1e18, "during lock: (1010 - 10) / 1000 = 1.0");
        assertEq(ppsAfterLock, 1.01e18, "after lock: 1010 / 1000 = 1.01");
    }

    /// @dev completeness: donating to amplify the lock-window dip is not a
    ///      profitable attack either way — the donation is only recovered
    ///      pro-rata, which is strictly less than the donation itself.
    ///      (Attacker net stays negative with and without the delta fix.)
    function test_DonationNotProfitableForAttacker() public {
        uint256 balBefore = want.balanceOf(attacker);
        want.mint(attacker, ATTACK_DEPOSIT);

        vm.startPrank(attacker);
        want.transfer(address(strat), DONATION);
        want.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        native.mint(address(strat), PROFIT);
        strat.harvest();

        vm.startPrank(attacker);
        vault.deposit(ATTACK_DEPOSIT);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1 seconds);

        vm.startPrank(attacker);
        vault.withdraw(vault.balanceOf(attacker));
        vm.stopPrank();

        int256 net = int256(want.balanceOf(attacker)) - int256(balBefore) - int256(ATTACK_DEPOSIT);
        emit log_named_int("attacker net (want wei)", net);
        assertLt(net, 0, "donation during lock window must be net-negative");
    }
}

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        unchecked {
            balanceOf[msg.sender] -= amount;
            balanceOf[to] += amount;
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance");
        unchecked {
            if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
        }
        return true;
    }
}

contract MockSwapper {
    /// @dev matches IBeefySwapper.swap which declares `returns (uint256 amountOut)`
    function swap(address from, address to, uint256 amount) external returns (uint256) {
        MockERC20(from).transferFrom(msg.sender, address(this), amount);
        MockERC20(to).transfer(msg.sender, amount);
        return amount;
    }
}

contract MockPool {
    function send(address token, address to, uint256 amount) external {
        MockERC20(token).transfer(to, amount);
    }
}

contract MockStrategy is BaseAllToNativeStrat {
    MockPool public pool;

    function init(
        address _want,
        address _native,
        MockPool _pool,
        address[] calldata _rewards,
        CommonAddresses calldata _common
    ) external initializer {
        __BaseStrategy_init(_want, _native, _rewards, _common);
        pool = _pool;
    }

    function balanceOfPool() public view override returns (uint256) {
        return IERC20(want).balanceOf(address(pool));
    }

    function _deposit(uint256 amount) internal override {
        IERC20(want).transfer(address(pool), amount);
    }

    function _withdraw(uint256 amount) internal override {
        pool.send(want, address(this), amount);
    }

    function _emergencyWithdraw() internal override {
        pool.send(want, address(this), IERC20(want).balanceOf(address(pool)));
    }

    function _claim() internal override {}

    function _verifyRewardToken(address) internal view override {}

    function _giveAllowances() internal override {
        IERC20(native).approve(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal override {
        IERC20(native).approve(unirouter, 0);
    }
}
