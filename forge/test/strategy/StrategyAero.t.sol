// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import {Clones} from "@openzeppelin-4/contracts/proxy/Clones.sol";
import {StrategyAero} from "../../../contracts/BIFI/strategies/Aero/StrategyAero.sol";
import {StratFeeManagerInitializable} from "../../../contracts/BIFI/strategies/Common/StratFeeManagerInitializable.sol";
import {
    IAeroRouter,
    IAeroPair,
    IAeroGauge,
    IAeroGaugeFactory,
    IAeroFactoryRegistry
} from "../../../contracts/BIFI/interfaces/aero/IAero.sol";
import {IFeeConfig} from "../../../contracts/BIFI/interfaces/common/IFeeConfig.sol";
import {IERC20Extended} from "../../../contracts/BIFI/interfaces/common/IERC20Extended.sol";
import {IStrategyFactory} from "../../../contracts/BIFI/interfaces/beefy/IStrategyFactory.sol";
import {BeefyVaultV7} from "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import {IStrategyV7} from "../../../contracts/BIFI/interfaces/beefy/IStrategyV7.sol";

contract AeroTestToken is ERC20 {
    uint8 private immutable tokenDecimals;

    constructor(uint8 _decimals) ERC20("Test", "TEST") {
        tokenDecimals = _decimals;
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AeroTestPair is AeroTestToken {
    address public token0;
    address public token1;
    address public factory = address(0xFAC);
    bytes32 public POOL_TYPE = bytes32("V2_VOLATILE");
    uint256 private reserve0 = 100 ether;
    uint256 private reserve1 = 100e6;

    constructor(address _token0, address _token1) AeroTestToken(18) {
        token0 = _token0;
        token1 = _token1;
    }

    function setPoolType(bytes32 kind) external {
        POOL_TYPE = kind;
    }

    function setReserves(uint256 r0, uint256 r1) external {
        reserve0 = r0;
        reserve1 = r1;
    }

    function getReserves() external view returns (uint256, uint256, uint256) {
        return (reserve0, reserve1, block.timestamp);
    }
}

contract AeroTestFeeConfig {
    uint256 public total = 0.1 ether;

    function setTotal(uint256 value) external {
        total = value;
    }

    function getFees(address) external view returns (IFeeConfig.FeeCategory memory) {
        return IFeeConfig.FeeCategory(total, 0.8 ether, 0.1 ether, 0.1 ether, "test", true);
    }
}

contract AeroTestGaugeFactory {
    uint256 public minStakeBlocks = 7;
    uint256 public penaltyRate = 1e6;
    bool public emergencyWithdrawEnabled;

    function setEmergencyWithdrawEnabled(bool enabled) external {
        emergencyWithdrawEnabled = enabled;
    }

    function setPenalty(uint256 blocks_, uint256 rate) external {
        minStakeBlocks = blocks_;
        penaltyRate = rate;
    }

    function effectivePenaltyConfig(address) external view returns (IAeroGaugeFactory.PenaltyConfig memory) {
        return IAeroGaugeFactory.PenaltyConfig(minStakeBlocks, penaltyRate);
    }
}

contract AeroTestGauge {
    address public stakingToken;
    address public voter = address(0xB07E);
    AeroTestGaugeFactory public gaugeFactory;
    AeroTestToken public reward;
    bool public isPool = true;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public depositBlock;
    mapping(address => uint256) public earned;
    uint256 public forfeited;

    constructor(address pool, AeroTestToken output, AeroTestGaugeFactory factory) {
        stakingToken = pool;
        reward = output;
        gaugeFactory = factory;
    }

    function setStakingToken(address token) external {
        stakingToken = token;
    }

    function setIsPool(bool value) external {
        isPool = value;
    }

    function setVoter(address value) external {
        voter = value;
    }

    function setEarned(address account, uint256 amount) external {
        earned[account] = amount;
    }

    function deposit(uint256 amount) external {
        require(amount > 0);
        IERC20(stakingToken).transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
        depositBlock[msg.sender] = block.number;
    }

    function withdraw(uint256 amount) external {
        require(amount > 0);
        _claim(msg.sender, msg.sender);
        balanceOf[msg.sender] -= amount;
        if (balanceOf[msg.sender] == 0) delete depositBlock[msg.sender];
        IERC20(stakingToken).transfer(msg.sender, amount);
    }

    function emergencyWithdraw(uint256 amount) external {
        require(gaugeFactory.emergencyWithdrawEnabled(), "emergency disabled");
        require(amount > 0);
        balanceOf[msg.sender] -= amount;
        if (balanceOf[msg.sender] == 0) delete depositBlock[msg.sender];
        IERC20(stakingToken).transfer(msg.sender, amount);
    }

    function claimEmissions(address account, address recipient) external {
        require(account == msg.sender);
        _claim(account, recipient);
    }

    function _claim(address account, address recipient) private {
        uint256 amount = earned[account];
        earned[account] = 0;
        if (block.number < depositBlock[account] + gaugeFactory.minStakeBlocks()) {
            uint256 penalty = amount * gaugeFactory.penaltyRate() / 1e6;
            forfeited += penalty;
            amount -= penalty;
        }
        reward.mint(recipient, amount);
    }
}

contract AeroTestSwapper {
    mapping(address => mapping(address => uint256)) public rate;
    uint256 public swaps;

    function setRate(address from, address to, uint256 value) external {
        rate[from][to] = value;
    }

    function getAmountOut(address from, address to, uint256 amount) public view returns (uint256) {
        return amount * rate[from][to] / 1 ether;
    }

    function swap(address from, address to, uint256 amount) external returns (uint256 out) {
        // Exact approvals are part of the contract with the strategy.
        require(IERC20(from).allowance(msg.sender, address(this)) == amount, "approval");
        require(rate[from][to] != 0, "missing route");
        IERC20(from).transferFrom(msg.sender, address(this), amount);
        out = getAmountOut(from, to, amount);
        IERC20(to).transfer(msg.sender, out);
        swaps++;
    }
}

contract AeroTestRouter {
    address public EMISSION_TOKEN;
    address public LEAF_VOTER = address(0xB07E);
    address public FACTORY_REGISTRY = address(this);
    mapping(address => address) public targetToGauge;
    AeroTestPair public pair;
    uint256 public executions;

    constructor(AeroTestPair pool, address output, address gauge) {
        pair = pool;
        EMISSION_TOKEN = output;
        targetToGauge[address(pool)] = gauge;
    }

    function setGauge(address value) external {
        targetToGauge[address(pair)] = value;
    }

    function setOutput(address value) external {
        EMISSION_TOKEN = value;
    }

    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external {
        require(keccak256(commands) == keccak256(hex"22") && inputs.length == 1 && deadline >= block.timestamp);
        IAeroRouter.AddLiquidityParams memory p = abi.decode(inputs[0], (IAeroRouter.AddLiquidityParams));
        require(p.factory == pair.factory() && p.tokenA == pair.token0() && p.tokenB == pair.token1());
        require(!p.createPool && p.payerAIsUser && p.payerBIsUser && p.recipient == msg.sender);
        require(p.spendA.mode == IAeroRouter.SpendMode.Amount && p.spendB.mode == IAeroRouter.SpendMode.Amount);
        require(p.liquidityMin > 0);
        (uint256 r0, uint256 r1,) = pair.getReserves();
        uint256 a0 = p.spendA.value;
        uint256 a1 = p.spendB.value;
        if (a0 * r1 / r0 <= a1) a1 = a0 * r1 / r0;
        else a0 = a1 * r0 / r1;
        IERC20(p.tokenA).transferFrom(msg.sender, address(pair), a0);
        IERC20(p.tokenB).transferFrom(msg.sender, address(pair), a1);
        uint256 minted = a0 * 1 ether / r0;
        require(minted >= p.liquidityMin);
        pair.mint(p.recipient, minted);
        executions++;
    }
}

contract AeroHarness is StrategyAero {
    function split(uint256 amount) external view returns (uint256, uint256) {
        return _liquiditySplit(amount);
    }

    function setLegacyWithdrawalFee(uint256 fee) external {
        withdrawalFee = fee;
    }
}

contract StrategyAeroTest is Test {
    address constant ROUTER = 0x0fEf9e88A7b76BCDBF451780C6774FE32965Ee98;
    address constant ALICE = address(0xA11CE);
    address constant BEEF = address(0xBEEF);
    AeroTestToken t0;
    AeroTestToken t1;
    AeroTestToken reward;
    AeroTestToken native;
    AeroTestPair pair;
    AeroTestGaugeFactory gf;
    AeroTestGauge gauge;
    AeroTestSwapper swapper;
    AeroTestFeeConfig fees;
    AeroHarness strategy;
    BeefyVaultV7 vault;

    function setUp() public {
        vm.roll(100);
        t0 = new AeroTestToken(18);
        t1 = new AeroTestToken(6);
        reward = new AeroTestToken(18);
        native = new AeroTestToken(18);
        pair = new AeroTestPair(address(t0), address(t1));
        gf = new AeroTestGaugeFactory();
        gauge = new AeroTestGauge(address(pair), reward, gf);
        swapper = new AeroTestSwapper();
        fees = new AeroTestFeeConfig();
        AeroTestRouter r = new AeroTestRouter(pair, address(reward), address(gauge));
        vm.etch(ROUTER, address(r).code);
        vm.store(ROUTER, bytes32(uint256(4)), bytes32(uint256(uint160(address(pair)))));
        vm.mockCall(ROUTER, abi.encodeWithSelector(IAeroRouter.FACTORY_REGISTRY.selector), abi.encode(ROUTER));
        vm.mockCall(ROUTER, abi.encodeWithSelector(IAeroRouter.EMISSION_TOKEN.selector), abi.encode(address(reward)));
        vm.mockCall(ROUTER, abi.encodeWithSelector(IAeroRouter.WETH.selector), abi.encode(address(native)));
        vm.mockCall(ROUTER, abi.encodeWithSelector(IAeroRouter.LEAF_VOTER.selector), abi.encode(gauge.voter()));
        vm.mockCall(
            ROUTER,
            abi.encodeWithSelector(IAeroFactoryRegistry.targetToGauge.selector, address(pair)),
            abi.encode(address(gauge))
        );
        swapper.setRate(address(reward), address(native), 2 ether);
        swapper.setRate(address(native), address(t0), 0.5 ether);
        swapper.setRate(address(native), address(t1), 0.5e6);
        t0.mint(address(swapper), 1e30);
        t1.mint(address(swapper), 1e24);
        native.mint(address(swapper), 1e30);
        vault = new BeefyVaultV7();
        strategy = _deploy();
        vault.initialize(IStrategyV7(address(strategy)), "Test", "TEST", 0);
    }

    function _common() internal view returns (StratFeeManagerInitializable.CommonAddresses memory) {
        return StratFeeManagerInitializable.CommonAddresses(
            address(vault), address(swapper), address(this), address(0x570A7), BEEF, address(fees)
        );
    }

    function _deploy() internal returns (AeroHarness s) {
        s = new AeroHarness();
        s.initialize(address(pair), _common());
    }

    function deployChecked() external returns (AeroHarness) {
        return _deploy();
    }

    function _deposit(uint256 amount) internal {
        pair.mint(ALICE, amount);
        vm.startPrank(ALICE, ALICE);
        pair.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
    }

    function testInitializationDiscoversAddressesAndDefaults() public view {
        assertEq(strategy.gauge(), address(gauge));
        assertEq(strategy.output(), address(reward));
        assertEq(strategy.native(), address(native));
        assertEq(strategy.aeroRouter(), ROUTER);
        assertFalse(strategy.harvestOnDeposit());
        assertEq(strategy.lockDuration(), 1 days);
        assertEq(strategy.withdrawFee(), 0);
    }

    function testInitializationValidation() public {
        vm.expectRevert("Initializable: contract is already initialized");
        strategy.initialize(address(pair), _common());
        vm.mockCall(
            ROUTER,
            abi.encodeWithSelector(IAeroFactoryRegistry.targetToGauge.selector, address(pair)),
            abi.encode(address(0))
        );
        vm.expectRevert("!gauge");
        this.deployChecked();
        vm.mockCall(
            ROUTER,
            abi.encodeWithSelector(IAeroFactoryRegistry.targetToGauge.selector, address(pair)),
            abi.encode(address(gauge))
        );
        gauge.setIsPool(false);
        vm.expectRevert("!pool gauge");
        this.deployChecked();
        gauge.setIsPool(true);
        gauge.setStakingToken(address(1));
        vm.expectRevert("!staking token");
        this.deployChecked();
        gauge.setStakingToken(address(pair));
        gauge.setVoter(address(1));
        vm.expectRevert("!voter");
        this.deployChecked();
        gauge.setVoter(address(0xB07E));
        pair.setPoolType(bytes32("CL"));
        vm.expectRevert(abi.encodeWithSelector(StrategyAero.UnsupportedPoolType.selector, bytes32("CL")));
        this.deployChecked();
    }

    function testDepositDelayAndVaultWithdrawal() public {
        _deposit(1 ether);
        assertEq(strategy.balanceOfPool(), 1 ether);
        assertEq(strategy.actionableBlock(), 107);
        vm.prank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(StrategyAero.ActionLocked.selector, 107));
        vault.withdrawAll();
        vm.roll(107);
        vm.prank(ALICE, ALICE);
        vault.withdrawAll();
        assertEq(pair.balanceOf(ALICE), 1 ether);
    }

    function testWithdrawalFeeRemainsZero() public {
        strategy.setHarvestOnDeposit(true);
        assertEq(strategy.withdrawFee(), 0);
        strategy.setHarvestOnDeposit(false);
        assertEq(strategy.withdrawFee(), 0);
        strategy.setWithdrawalFee(10);
        assertEq(strategy.withdrawFee(), 0);
    }

    function testFuzzConfiguredWithdrawalFeeIsNotCharged(uint256 fee) public {
        fee = bound(fee, 0, strategy.WITHDRAWAL_FEE_CAP());
        strategy.setWithdrawalFee(fee);
        assertEq(strategy.withdrawFee(), 0);
        assertEq(strategy.getAllFees().withdraw, 0);
        _deposit(1 ether);
        vm.roll(107);
        vm.prank(ALICE, ALICE);
        vault.withdrawAll();
        assertEq(pair.balanceOf(ALICE), 1 ether);
    }

    function testWithdrawalFeeSetterRequiresManager() public {
        vm.prank(ALICE);
        vm.expectRevert(bytes("!manager"));
        strategy.setWithdrawalFee(0);
    }

    function testFuzzLegacyFeeDoesNotAffectWithdrawals(bool harvestOnDeposit) public {
        strategy.setHarvestOnDeposit(harvestOnDeposit);
        strategy.setLegacyWithdrawalFee(10);
        assertEq(strategy.withdrawFee(), 0);
        assertEq(strategy.getAllFees().withdraw, 0);
        _deposit(1 ether);
        vm.roll(107);
        vm.prank(ALICE, ALICE);
        vault.withdrawAll();
        assertEq(pair.balanceOf(ALICE), 1 ether);
    }

    function testHarvestRewardsAndFees() public {
        _deposit(1 ether);
        vm.roll(107);
        gauge.setEarned(address(strategy), 100 ether);
        assertEq(strategy.callReward(), 2 ether);
        strategy.harvest(address(0xCA11));
        assertEq(native.balanceOf(address(0xCA11)), 2 ether);
        assertEq(native.balanceOf(BEEF), 16 ether);
        assertEq(strategy.balanceOfPool(), 1.45 ether);
        assertEq(strategy.actionableBlock(), 114);
    }

    function testProfitUnlocksAndCarriesOverOnNextHarvest() public {
        _deposit(100 ether);
        vm.roll(107);
        gauge.setEarned(address(strategy), 100 ether);
        strategy.harvest();
        assertEq(strategy.totalLocked(), 0.45 ether);
        assertEq(strategy.lockedProfit(), 0.45 ether);
        assertEq(strategy.balanceOf(), 100 ether);

        vm.warp(block.timestamp + 12 hours);
        assertEq(strategy.lockedProfit(), 0.225 ether);
        assertEq(strategy.balanceOf(), 100.225 ether);
        vm.roll(114);
        gauge.setEarned(address(strategy), 100 ether);
        strategy.harvest();
        assertEq(strategy.totalLocked(), 0.675 ether);
        assertEq(strategy.balanceOf(), 100.225 ether);

        vm.warp(block.timestamp + 1 days);
        assertEq(strategy.lockedProfit(), 0);
        assertEq(strategy.balanceOf(), 100.9 ether);
    }

    function testProfitLockAffectsVaultShares() public {
        _deposit(100 ether);
        vm.roll(107);
        gauge.setEarned(address(strategy), 100 ether);
        strategy.harvest();
        vm.roll(114);
        pair.mint(address(0xB0B), 100 ether);
        vm.startPrank(address(0xB0B), address(0xB0B));
        pair.approve(address(vault), 100 ether);
        vault.deposit(100 ether);
        vm.stopPrank();
        assertEq(vault.balanceOf(address(0xB0B)), 100 ether);
        vm.warp(block.timestamp + 1 days);
        assertEq(strategy.balanceOf(), 200.45 ether);
    }

    function testLockDurationPermissionsAndHarvestOnDeposit() public {
        vm.prank(ALICE);
        vm.expectRevert("!manager");
        strategy.setLockDuration(1 hours);
        strategy.setLockDuration(1 hours);
        strategy.setHarvestOnDeposit(true);
        assertEq(strategy.lockDuration(), 0);
        strategy.setHarvestOnDeposit(false);
        assertEq(strategy.lockDuration(), 1 days);
    }

    function testHarvestOnDepositPricesSharesAfterHarvest() public {
        _deposit(100 ether);
        strategy.setHarvestOnDeposit(true);
        vm.roll(107);
        gauge.setEarned(address(strategy), 100 ether);
        pair.mint(address(0xB0B), 100 ether);
        vm.startPrank(address(0xB0B), address(0xB0B));
        pair.approve(address(vault), 100 ether);
        vault.deposit(100 ether);
        vm.stopPrank();
        assertEq(vault.balanceOf(address(0xB0B)), uint256(100 ether) * 100 ether / 100.45 ether);
        assertEq(strategy.balanceOfPool(), 200.45 ether);
    }

    function testPanicNormalAndEmergencyAndPausedWithdrawal() public {
        _deposit(1 ether);
        strategy.panic();
        assertTrue(strategy.paused());
        assertEq(strategy.balanceOfWant(), 1 ether);
        strategy.unpause();
        gf.setEmergencyWithdrawEnabled(true);
        vm.mockCallRevert(
            address(gauge), abi.encodeWithSelector(IAeroGauge.withdraw.selector), bytes("normal unavailable")
        );
        strategy.panic();
        assertEq(strategy.balanceOfWant(), 1 ether);
        vm.prank(ALICE, ALICE);
        vault.withdrawAll();
        assertEq(pair.balanceOf(ALICE), 1 ether);
    }

    function testPanicFailureRollsBackPause() public {
        _deposit(1 ether);
        vm.mockCallRevert(
            address(gauge), abi.encodeWithSelector(IAeroGauge.withdraw.selector), bytes("normal unavailable")
        );
        vm.expectRevert(bytes("normal unavailable"));
        strategy.panic();
        assertFalse(strategy.paused());
        assertEq(strategy.balanceOfPool(), 1 ether);
    }

    function testManagerAndVaultAuthorization() public {
        vm.startPrank(ALICE);
        vm.expectRevert("!manager");
        strategy.panic();
        vm.expectRevert("!manager");
        strategy.setHarvestOnDeposit(true);
        vm.expectRevert("!vault");
        strategy.withdraw(1);
        vm.expectRevert("!vault");
        strategy.retireStrat();
        vm.stopPrank();
    }

    function testStableRatioAndZeroReserves() public {
        pair.setPoolType(bytes32("V2_STABLE"));
        pair.setReserves(200 ether, 100e6);
        AeroHarness s = _deploy();
        (uint256 a, uint256 b) = s.split(90 ether);
        assertEq(a, 60 ether);
        assertEq(b, 30 ether);
        pair.setReserves(0, 100e6);
        vm.expectRevert(StrategyAero.InvalidLiquidity.selector);
        s.split(90 ether);
    }

    function testSwapFailureRestoresClaim() public {
        _deposit(1 ether);
        vm.roll(107);
        gauge.setEarned(address(strategy), 100 ether);
        swapper.setRate(address(reward), address(native), 0);
        vm.expectRevert("missing route");
        strategy.harvest();
        assertEq(gauge.earned(address(strategy)), 100 ether);
        assertEq(strategy.balanceOfPool(), 1 ether);
    }

    function testWithdrawalClaimsRewardsForNextHarvest() public {
        _deposit(1 ether);
        vm.roll(107);
        gauge.setEarned(address(strategy), 40 ether);
        vm.prank(ALICE, ALICE);
        vault.withdraw(0.5 ether);
        assertEq(reward.balanceOf(address(strategy)), 40 ether);
        gauge.setEarned(address(strategy), 60 ether);
        assertEq(strategy.rewardsAvailable(), 100 ether);
        strategy.harvest(address(0xCA11));
        assertEq(native.balanceOf(BEEF), 16 ether);
    }

    function testZeroRewardsAndDynamicPenalty() public {
        _deposit(1 ether);
        gf.setPenalty(20, 1e6);
        assertEq(strategy.actionableBlock(), 120);
        gf.setPenalty(20, 0);
        assertTrue(strategy.actionable());
        strategy.harvest();
        assertEq(strategy.lastHarvest(), 0);
        assertEq(swapper.swaps(), 0);
    }

    function testEmptyPanicAndAlreadyPausedPanic() public {
        strategy.panic();
        assertTrue(strategy.paused());
        strategy.panic();
        assertEq(strategy.balanceOf(), 0);
    }

    function testHarvestOnDepositPermissionsAndFee() public {
        strategy.setHarvestOnDeposit(true);
        assertEq(strategy.withdrawFee(), 0);
        vm.prank(ALICE);
        vm.expectRevert("!vault");
        strategy.beforeDeposit();
        strategy.setHarvestOnDeposit(false);
        assertEq(strategy.withdrawFee(), 0);
    }

    function testRetirementWaitsForUnlock() public {
        _deposit(1 ether);
        vm.prank(address(vault));
        vm.expectRevert(abi.encodeWithSelector(StrategyAero.ActionLocked.selector, 107));
        strategy.retireStrat();
        vm.roll(107);
        vm.prank(address(vault));
        strategy.retireStrat();
        assertEq(pair.balanceOf(address(vault)), 1 ether);
    }
}

/// @dev Pinned Arbitrum fork: gauge implementation is real; registration,
/// voter settlement, pair, and L1/L2 clock readings are simulated.
interface ITestGaugeInit {
    function initialize(address, address, bool) external;
}

contract StrategyAeroArbitrumForkTest is Test {
    uint256 constant HEIGHT = 520607892;
    address constant ROUTER = 0x0fEf9e88A7b76BCDBF451780C6774FE32965Ee98;
    address constant IMPLEMENTATION = 0x6E3b800DCC9a7e6b91239FEf0f8141F430EBCf84;
    IAeroGauge gauge;
    StrategyAero strategy;
    AeroTestPair pair;
    address factory;

    function setUp() public {
        vm.createSelectFork("https://arb-one.api.pocket.network", HEIGHT);
        vm.roll(26328024);
        _clock(HEIGHT);
        pair = new AeroTestPair(address(new AeroTestToken(18)), address(new AeroTestToken(18)));
        gauge = IAeroGauge(Clones.clone(IMPLEMENTATION));
        ITestGaugeInit(address(gauge)).initialize(address(pair), address(0xBEEF), true);
        factory = gauge.gaugeFactory();
        vm.mockCall(
            gauge.voter(), abi.encodeWithSignature("settleGauge(address)", address(gauge)), abi.encode(uint256(0))
        );
        vm.mockCall(
            IAeroRouter(ROUTER).FACTORY_REGISTRY(),
            abi.encodeWithSelector(IAeroFactoryRegistry.targetToGauge.selector, address(pair)),
            abi.encode(address(gauge))
        );
        strategy = new StrategyAero();
        strategy.initialize(
            address(pair),
            StratFeeManagerInitializable.CommonAddresses(
                address(this),
                address(new AeroTestSwapper()),
                address(this),
                address(0x570A7),
                address(0xBEEF),
                address(new AeroTestFeeConfig())
            )
        );
    }

    function _clock(uint256 n) internal {
        vm.mockCall(address(0x64), abi.encodeWithSignature("arbBlockNumber()"), abi.encode(n));
    }

    function _penalty(uint256 n) internal {
        vm.mockCall(
            factory,
            abi.encodeWithSelector(IAeroGaugeFactory.effectivePenaltyConfig.selector, address(gauge)),
            abi.encode(IAeroGaugeFactory.PenaltyConfig(n, 1e6))
        );
    }

    function testArbitrumDelayAndWithdrawal() public {
        _penalty(7);
        pair.mint(address(strategy), 1 ether);
        strategy.deposit();
        assertEq(strategy.lastGaugeDepositBlock(), HEIGHT);
        assertFalse(strategy.actionable());
        vm.expectRevert(abi.encodeWithSelector(StrategyAero.ActionLocked.selector, HEIGHT + 7));
        strategy.withdraw(1 ether);
        _clock(HEIGHT + 7);
        assertTrue(strategy.actionable());
        strategy.setWithdrawalFee(0);
        strategy.withdraw(1 ether);
        assertEq(pair.balanceOf(address(this)), 1 ether);
    }

    function testArbitrumZeroDelayAndEmergencyPanic() public {
        _penalty(0);
        pair.mint(address(strategy), 1 ether);
        strategy.deposit();
        assertTrue(strategy.actionable());
        vm.mockCall(
            factory, abi.encodeWithSelector(IAeroGaugeFactory.emergencyWithdrawEnabled.selector), abi.encode(true)
        );
        vm.mockCallRevert(
            gauge.voter(), abi.encodeWithSignature("settleGauge(address)", address(gauge)), bytes("unavailable")
        );
        strategy.panic();
        assertTrue(strategy.paused());
        assertEq(strategy.balanceOfWant(), 1 ether);
    }
}
