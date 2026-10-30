// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import {StrategyAero} from "../../../contracts/BIFI/strategies/Aero/StrategyAero.sol";
import {StratFeeManagerInitializable} from "../../../contracts/BIFI/strategies/Common/StratFeeManagerInitializable.sol";
import {IAeroRouter} from "../../../contracts/BIFI/interfaces/aero/IAeroRouter.sol";
import {IAeroPair} from "../../../contracts/BIFI/interfaces/aero/IAeroPair.sol";
import {IAeroGauge} from "../../../contracts/BIFI/interfaces/aero/IAeroGauge.sol";
import {IAeroGaugeFactory} from "../../../contracts/BIFI/interfaces/aero/IAeroGaugeFactory.sol";
import {IAeroFactoryRegistry} from "../../../contracts/BIFI/interfaces/aero/IAeroFactoryRegistry.sol";
import {IFeeConfig} from "../../../contracts/BIFI/interfaces/common/IFeeConfig.sol";

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

contract AeroTestHarness is StrategyAero {
    function liquiditySplit(uint256 amount) external view returns (uint256, uint256) {
        return _liquiditySplit(amount);
    }

    function addLiquidity(uint256 amount) external {
        _addLiquidity(amount);
    }
}

/// @notice Deterministic accounting, configuration, penalty and authorization tests.
contract StrategyAeroTest is Test {
    AeroTestToken private token0;
    AeroTestToken private token1;
    AeroTestToken private output;
    AeroTestToken private native;
    AeroTestPair private pair;
    AeroTestGauge private gauge;
    AeroTestGaugeFactory private gaugeFactory;
    AeroTestFeeConfig private fees;
    AeroTestSwapper private swapper;
    AeroTestRouter private router;
    AeroTestHarness private strategy;
    address private constant CALLER = address(0xCA11);
    address private constant STRATEGIST = address(0x570A7);
    address private constant BEEFY = address(0xBEEF);

    function setUp() public {
        vm.roll(100);
        token0 = new AeroTestToken(18);
        token1 = new AeroTestToken(6);
        output = new AeroTestToken(18);
        native = new AeroTestToken(18);
        pair = new AeroTestPair(address(token0), address(token1));
        gaugeFactory = new AeroTestGaugeFactory();
        gauge = new AeroTestGauge(address(pair), output, gaugeFactory);
        fees = new AeroTestFeeConfig();
        swapper = new AeroTestSwapper();
        router = new AeroTestRouter(pair, address(output), address(gauge));
        swapper.setRate(address(output), address(token0), 1 ether);
        swapper.setRate(address(output), address(token1), 1e6);
        swapper.setRate(address(output), address(native), 2 ether);
        swapper.setRate(address(native), address(token0), 0.5 ether);
        swapper.setRate(address(native), address(token1), 0.5e6);
        token0.mint(address(swapper), 1e30);
        token1.mint(address(swapper), 1e24);
        native.mint(address(swapper), 1e30);
        strategy = _deploy(false);
    }

    function _deploy(bool hod) private returns (AeroTestHarness s) {
        s = new AeroTestHarness();
        s.initialize(address(pair), address(gauge), address(output), address(native), address(router), hod, _common());
    }

    function createStrategy(bool hod) external returns (AeroTestHarness) {
        return _deploy(hod);
    }

    function _common() private view returns (StratFeeManagerInitializable.CommonAddresses memory) {
        return StratFeeManagerInitializable.CommonAddresses(
            address(this), address(swapper), address(this), STRATEGIST, BEEFY, address(fees)
        );
    }

    function _stake() private {
        pair.mint(address(strategy), 1 ether);
        strategy.deposit();
    }

    function testInitializeSetsGaugeAndRewardWithoutAllowances() public view {
        assertEq(strategy.gauge(), address(gauge));
        assertEq(strategy.output(), address(output));
        assertFalse(strategy.harvestOnDeposit());
        assertEq(strategy.withdrawFee(), 10);
        assertEq(pair.allowance(address(strategy), address(gauge)), 0);
        assertEq(output.allowance(address(strategy), address(swapper)), 0);
        assertEq(token0.allowance(address(strategy), address(router)), 0);
    }

    function testHarvestOnDepositInitializationAndManagerToggle() public {
        AeroTestHarness s = _deploy(true);
        assertTrue(s.harvestOnDeposit());
        assertEq(s.withdrawFee(), 0);
        s.setHarvestOnDeposit(false);
        assertEq(s.withdrawFee(), 10);
        vm.prank(CALLER);
        vm.expectRevert("!manager");
        s.setHarvestOnDeposit(true);
    }

    function testCannotReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        strategy.initialize(
            address(pair), address(gauge), address(output), address(native), address(router), false, _common()
        );
    }

    function testRejectsZeroGauge() public {
        StrategyAero s = new StrategyAero();
        vm.expectRevert(StrategyAero.InvalidInput.selector);
        s.initialize(address(pair), address(0), address(output), address(native), address(router), false, _common());
    }

    function testRejectsCLPool() public {
        pair.setPoolType(bytes32("CL"));
        vm.expectRevert(abi.encodeWithSelector(StrategyAero.UnsupportedPoolType.selector, bytes32("CL")));
        this.createStrategy(false);
    }

    function testRejectsGaugeForAnotherPool() public {
        gauge.setStakingToken(address(123));
        vm.expectRevert(StrategyAero.InvalidInput.selector);
        this.createStrategy(false);
    }

    function testRejectsGaugeNotRegisteredForPool() public {
        router.setGauge(address(123));
        vm.expectRevert(StrategyAero.InvalidInput.selector);
        this.createStrategy(false);
    }

    function testRejectsNonPoolGauge() public {
        gauge.setIsPool(false);
        vm.expectRevert(StrategyAero.InvalidInput.selector);
        this.createStrategy(false);
    }

    function testRejectsWrongVoter() public {
        gauge.setVoter(address(123));
        vm.expectRevert(StrategyAero.InvalidInput.selector);
        this.createStrategy(false);
    }

    function testRejectsWrongRewardToken() public {
        router.setOutput(address(123));
        vm.expectRevert(StrategyAero.InvalidInput.selector);
        this.createStrategy(false);
    }

    function testDirectDepositAndWithdrawConsumeExactApproval() public {
        strategy.setWithdrawalFee(0);
        _stake();
        assertEq(strategy.balanceOfPool(), 1 ether);
        assertEq(pair.allowance(address(strategy), address(gauge)), 0);
        assertEq(strategy.actionableBlock(), 107);
        vm.roll(107);
        assertTrue(strategy.actionable());
        strategy.withdraw(0.4 ether);
        assertEq(strategy.balanceOfPool(), 0.6 ether);
        assertEq(pair.balanceOf(address(this)), 0.4 ether);
        strategy.withdraw(0.6 ether);
        assertEq(strategy.balanceOfPool(), 0);
        assertEq(strategy.lastGaugeDepositBlock(), 0);
    }

    function testDepositWithdrawHarvestAndRetireRespectPenaltyWindow() public {
        _stake();
        uint256 unlock = strategy.actionableBlock();
        pair.mint(address(strategy), 1);
        vm.expectRevert(abi.encodeWithSelector(StrategyAero.ActionLocked.selector, unlock));
        strategy.deposit();
        vm.expectRevert(abi.encodeWithSelector(StrategyAero.ActionLocked.selector, unlock));
        strategy.withdraw(1 ether);
        vm.expectRevert(abi.encodeWithSelector(StrategyAero.ActionLocked.selector, unlock));
        strategy.harvest();
        vm.expectRevert(abi.encodeWithSelector(StrategyAero.ActionLocked.selector, unlock));
        strategy.retireStrat();
        assertEq(strategy.callReward(), 0);
        vm.roll(unlock - 1);
        assertFalse(strategy.actionable());
        vm.roll(unlock);
        assertTrue(strategy.actionable());
        strategy.retireStrat();
        assertEq(strategy.balanceOfPool(), 0);
    }

    function testPenaltyConfigurationChangesAreReadDynamically() public {
        _stake();
        gaugeFactory.setPenalty(20, 1e6);
        assertEq(strategy.actionableBlock(), 120);
        gaugeFactory.setPenalty(20, 0);
        assertEq(strategy.minStakeBlocks(), 0);
        assertTrue(strategy.actionable());
        strategy.withdraw(1 ether);
    }

    function testWithdrawAndRetireAreVaultOnly() public {
        vm.startPrank(CALLER);
        vm.expectRevert("!vault");
        strategy.withdraw(1);
        vm.expectRevert("!vault");
        strategy.retireStrat();
        vm.stopPrank();
    }

    function testPanicAcceptsPenaltyAndUnpauseRestakes() public {
        _stake();
        gauge.setEarned(address(strategy), 100 ether);
        strategy.panic();
        assertTrue(strategy.paused());
        assertEq(strategy.balanceOfPool(), 0);
        assertEq(strategy.balanceOfWant(), 1 ether);
        assertEq(gauge.forfeited(), 100 ether);
        vm.expectRevert("Pausable: paused");
        strategy.deposit();
        strategy.withdraw(0.25 ether);
        assertEq(pair.balanceOf(address(this)), 0.25 ether);
        strategy.unpause();
        assertEq(strategy.balanceOfPool(), 0.75 ether);
    }

    function testPauseDoesNotBypassNormalWithdrawalDelay() public {
        _stake();
        strategy.pause();
        vm.expectRevert(abi.encodeWithSelector(StrategyAero.ActionLocked.selector, 107));
        strategy.withdraw(1 ether);
        vm.roll(107);
        strategy.withdraw(1 ether);
        assertEq(pair.balanceOf(address(this)), 1 ether);
    }

    function testHarvestClaimsChargesFeesMintsLpAndRestakes() public {
        _stake();
        vm.roll(107);
        gauge.setEarned(address(strategy), 100 ether);
        assertEq(strategy.rewardsAvailable(), 100 ether);
        assertEq(strategy.callReward(), 2 ether);
        strategy.harvest(CALLER);
        assertEq(native.balanceOf(CALLER), 2 ether);
        assertEq(native.balanceOf(STRATEGIST), 2 ether);
        assertEq(native.balanceOf(BEEFY), 16 ether);
        assertEq(strategy.balanceOfPool(), 1.45 ether);
        assertEq(output.balanceOf(address(strategy)), 0);
        assertEq(strategy.lastHarvest(), block.timestamp);
        assertEq(strategy.actionableBlock(), 114);
        assertEq(output.allowance(address(strategy), address(swapper)), 0);
        assertEq(token0.allowance(address(strategy), address(router)), 0);
        assertEq(token1.allowance(address(strategy), address(router)), 0);
    }

    function testWithdrawnEmissionsAreHarvestedFromFullOutputBalance() public {
        _stake();
        vm.roll(107);
        gauge.setEarned(address(strategy), 40 ether);
        strategy.withdraw(0.5 ether);
        assertEq(output.balanceOf(address(strategy)), 40 ether);
        gauge.setEarned(address(strategy), 60 ether);
        assertEq(strategy.rewardsAvailable(), 100 ether);
        assertEq(strategy.callReward(), 2 ether);
        strategy.harvest(CALLER);
        assertEq(native.balanceOf(CALLER), 2 ether);
        assertEq(output.balanceOf(address(strategy)), 0);
        // The retained 0.1% withdrawal fee is also restaked by harvest.
        assertEq(strategy.balanceOfPool(), 0.9505 ether);
    }

    function testPreexistingNativeIsNotDistributedAsPerformanceFees() public {
        native.mint(address(strategy), 123 ether);
        output.mint(address(strategy), 100 ether);
        strategy.harvest(CALLER);
        assertEq(native.balanceOf(address(strategy)), 123 ether);
        assertEq(native.balanceOf(BEEFY), 16 ether);
    }

    function testRewardEqualToNativeChargesOnlyConfiguredFee() public {
        AeroTestHarness s = new AeroTestHarness();
        s.initialize(address(pair), address(gauge), address(output), address(output), address(router), false, _common());
        output.mint(address(s), 100 ether);
        s.harvest(CALLER);
        assertEq(output.balanceOf(CALLER), 1 ether);
        assertEq(output.balanceOf(STRATEGIST), 1 ether);
        assertEq(output.balanceOf(BEEFY), 8 ether);
        assertEq(s.balanceOfPool(), 0.45 ether);
    }

    function testRewardIsToken1AndNativeIsToken0PreservesLpDust() public {
        AeroTestGauge g = new AeroTestGauge(address(pair), token1, gaugeFactory);
        AeroTestRouter r = new AeroTestRouter(pair, address(token1), address(g));
        swapper.setRate(address(token1), address(token0), 1e30);
        swapper.setRate(address(token0), address(token1), 1e6);
        AeroTestHarness s = new AeroTestHarness();
        s.initialize(address(pair), address(g), address(token1), address(token0), address(r), false, _common());
        token1.mint(address(s), 100e6);
        token0.mint(address(s), 7 ether);
        s.harvest(CALLER);
        assertEq(token0.balanceOf(CALLER), 1 ether);
        assertEq(token0.balanceOf(STRATEGIST), 1 ether);
        assertEq(token0.balanceOf(BEEFY), 8 ether);
        assertEq(s.balanceOfPool(), 0.45 ether);
        assertEq(token0.balanceOf(address(s)), 7 ether);
        assertEq(token0.allowance(address(s), address(r)), 0);
        assertEq(token1.allowance(address(s), address(r)), 0);
    }

    function testPausedHarvestAndNonManagerPanicRevert() public {
        vm.prank(CALLER);
        vm.expectRevert("!manager");
        strategy.panic();
        strategy.pause();
        vm.expectRevert("Pausable: paused");
        strategy.harvest(CALLER);
    }

    function testZeroRewardsDoesNotSwapOrMint() public {
        strategy.harvest(CALLER);
        assertEq(swapper.swaps(), 0);
        assertEq(router.executions(), 0);
        assertEq(strategy.lastHarvest(), 0);
        strategy.withdraw(0);
        strategy.retireStrat();
    }

    function testZeroPerformanceFeeSkipsFeeSwap() public {
        fees.setTotal(0);
        output.mint(address(strategy), 100 ether);
        strategy.harvest(CALLER);
        assertEq(native.balanceOf(CALLER), 0);
        assertEq(swapper.swaps(), 3);
        assertEq(strategy.balanceOfPool(), 0.5 ether);
    }

    function testHarvestOnDepositIsVaultOnly() public {
        AeroTestHarness s = _deploy(true);
        vm.prank(CALLER);
        vm.expectRevert("!vault");
        s.beforeDeposit();
        output.mint(address(s), 100 ether);
        s.beforeDeposit();
        // Complete the vault's beforeDeposit -> transfer new LP -> deposit
        // sequence in the same block. The hook must not start a fresh lock.
        assertGt(s.balanceOfWant(), 0);
        assertEq(s.balanceOfPool(), 0);
        pair.mint(address(s), 1 ether);
        s.deposit();
        assertGt(s.balanceOfPool(), 0);
    }

    function testHarvestOnDepositAfterExistingStakeCanFinishVaultDeposit() public {
        AeroTestHarness s = _deploy(true);
        pair.mint(address(s), 1 ether);
        s.deposit();
        vm.roll(s.actionableBlock());
        gauge.setEarned(address(s), 100 ether);
        s.beforeDeposit();
        pair.mint(address(s), 1 ether);
        s.deposit();
        assertEq(s.balanceOfPool(), 2.45 ether);
    }

    function testPanicCanExitAnAlreadyPausedStrategy() public {
        _stake();
        strategy.pause();
        strategy.panic();
        assertEq(strategy.balanceOfPool(), 0);
        assertEq(strategy.balanceOfWant(), 1 ether);
    }

    function testUnirouterCanChangeWithoutAllowanceMigration() public {
        AeroTestSwapper replacement = new AeroTestSwapper();
        replacement.setRate(address(output), address(token0), 1 ether);
        replacement.setRate(address(output), address(token1), 1e6);
        replacement.setRate(address(output), address(native), 2 ether);
        replacement.setRate(address(native), address(token0), 0.5 ether);
        replacement.setRate(address(native), address(token1), 0.5e6);
        token0.mint(address(replacement), 100 ether);
        token1.mint(address(replacement), 100e6);
        native.mint(address(replacement), 300 ether);
        strategy.setUnirouter(address(replacement));
        output.mint(address(strategy), 100 ether);
        strategy.harvest(CALLER);
        assertEq(swapper.swaps(), 0);
        assertEq(replacement.swaps(), 3);
    }

    function testStableSplitUsesRawReservesWithMixedDecimals() public {
        pair.setPoolType(bytes32("V2_STABLE"));
        pair.setReserves(200 ether, 100e6);
        AeroTestHarness s = _deploy(false);
        (uint256 a0, uint256 a1) = s.liquiditySplit(90 ether);
        assertEq(a0, 60 ether);
        assertEq(a1, 30 ether);
        output.mint(address(s), 100 ether);
        s.harvest(CALLER);
        assertEq(s.balanceOfPool(), 0.3 ether);
        assertEq(token0.balanceOf(address(s)), 0);
        assertEq(token1.balanceOf(address(s)), 0);
    }

    function testStableSplitRejectsZeroQuotesAndEmptyReserves() public {
        pair.setPoolType(bytes32("V2_STABLE"));
        AeroTestHarness s = _deploy(false);
        swapper.setRate(address(native), address(token1), 0);
        vm.expectRevert(StrategyAero.InvalidLiquidity.selector);
        s.liquiditySplit(100 ether);
        swapper.setRate(address(native), address(token1), 0.5e6);
        pair.setReserves(0, 100e6);
        vm.expectRevert(StrategyAero.InvalidLiquidity.selector);
        s.liquiditySplit(100 ether);
    }

    function testFuzzStableSplitTracksReserveRatio(uint64 r0, uint64 r1, uint64 amount) public {
        r0 = uint64(bound(r0, 1, 1e6));
        r1 = uint64(bound(r1, 1, 1e6));
        amount = uint64(bound(amount, 2, 1e6));
        pair.setPoolType(bytes32("V2_STABLE"));
        pair.setReserves(uint256(r0) * 1 ether, uint256(r1) * 1e6);
        AeroTestHarness s = _deploy(false);
        (uint256 a0, uint256 a1) = s.liquiditySplit(uint256(amount) * 1 ether);
        uint256 expected = uint256(amount) * 1 ether * r0 / (uint256(r0) + r1);
        assertApproxEqAbs(a0, expected, 1e12);
        assertEq(a0 + a1, uint256(amount) * 1 ether);
    }
}

interface IAeroTestLivePair {
    function mint(address recipient) external returns (uint256);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

/// @dev Implements the Beefy Swapper API while performing genuine live-pair swaps.
///      This avoids relying on production Beefy route configuration in a fork.
contract AeroLivePairSwapper {
    IAeroPair public immutable pair;

    constructor(address pool) {
        pair = IAeroPair(pool);
    }

    function getAmountOut(address from, address, uint256 amount) external view returns (uint256) {
        return pair.getAmountOut(amount, from);
    }

    function swap(address from, address to, uint256 amount) external returns (uint256 out) {
        require((from == pair.token0() && to == pair.token1()) || (from == pair.token1() && to == pair.token0()));
        out = pair.getAmountOut(amount, from);
        IERC20(from).transferFrom(msg.sender, address(pair), amount);
        IAeroTestLivePair(address(pair))
            .swap(to == pair.token0() ? out : 0, to == pair.token1() ? out : 0, msg.sender, "");
    }
}

/// @notice Real Base pair swaps, Metarouter minting and direct gauge interaction.
/// @dev BASE_RPC defaults to the public RPC. Set BASE_FORK_BLOCK to pin a run
///      when using an RPC with historical-state support.
contract StrategyAeroForkTest is Test {
    address private constant AERO = 0x3f5bF3EdAc59d650D8fDf9657a71F2f904A3a4Ee;
    address private constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address private constant PAIR = 0xF634058dC94e6BF8e828E27621320C423bC8B18E;
    address private constant GAUGE = 0xd424BA8ca9d4E278753DE76651a0095451e65cD1;
    address private constant ROUTER = 0x0fEf9e88A7b76BCDBF451780C6774FE32965Ee98;
    AeroTestHarness private strategy;
    AeroTestFeeConfig private fees;
    AeroLivePairSwapper private swapper;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_RPC", string("https://base.api.pocket.network"));
        uint256 forkBlock = vm.envOr("BASE_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, forkBlock);
        fees = new AeroTestFeeConfig();
        swapper = new AeroLivePairSwapper(PAIR);
        strategy = new AeroTestHarness();
        strategy.initialize(
            PAIR,
            GAUGE,
            AERO,
            USDC,
            ROUTER,
            false,
            StratFeeManagerInitializable.CommonAddresses(
                address(this), address(swapper), address(this), address(0x570A7), address(0xBEEF), address(fees)
            )
        );
    }

    /// @dev Mint genuine LP, exercising the pair's transfer hooks and fee indexes.
    function _mintLp(address recipient) private returns (uint256 lp) {
        (uint256 r0, uint256 r1,) = IAeroPair(PAIR).getReserves();
        uint256 amount0 = r0 / 1000000;
        uint256 amount1 = r1 / 1000000;
        deal(AERO, address(this), amount0);
        deal(USDC, address(this), amount1);
        IERC20(AERO).transfer(PAIR, amount0);
        IERC20(USDC).transfer(PAIR, amount1);
        lp = IAeroTestLivePair(PAIR).mint(recipient);
    }

    function testLiveDirectDepositAndWithdrawalAtUnlockBlock() public {
        _enablePenalty();
        uint256 lp = _mintLp(address(strategy));
        strategy.deposit();
        assertEq(strategy.balanceOfPool(), lp);
        assertEq(IERC20(PAIR).allowance(address(strategy), GAUGE), 0);
        assertEq(IAeroGauge(GAUGE).depositBlock(address(strategy)), block.number);
        vm.expectRevert(abi.encodeWithSelector(StrategyAero.ActionLocked.selector, strategy.actionableBlock()));
        strategy.withdraw(lp);
        vm.roll(strategy.actionableBlock());
        strategy.setWithdrawalFee(0);
        strategy.withdraw(lp);
        assertEq(strategy.balanceOfPool(), 0);
        assertEq(IERC20(PAIR).balanceOf(address(this)), lp);
    }

    function testLiveMetarouterMintsLpAndClearsLiquidityApprovals() public {
        (uint256 r0, uint256 r1,) = IAeroPair(PAIR).getReserves();
        deal(AERO, address(strategy), r0 / 1000000);
        deal(USDC, address(strategy), r1 / 1000000);
        strategy.addLiquidity(0);
        assertGt(strategy.balanceOfWant(), 0);
        assertEq(IERC20(AERO).allowance(address(strategy), ROUTER), 0);
        assertEq(IERC20(USDC).allowance(address(strategy), ROUTER), 0);
    }

    function testLiveHarvestSwapsChargesFeesMintsAndStakes() public {
        _enablePenalty();
        deal(AERO, address(strategy), 100 ether);
        uint256 quotedCall = strategy.callReward();
        assertGt(quotedCall, 0);
        strategy.harvest(address(0xCA11));
        assertGt(IERC20(USDC).balanceOf(address(0xCA11)), 0);
        assertGt(IERC20(USDC).balanceOf(address(0xBEEF)), 0);
        assertGt(strategy.balanceOfPool(), 0);
        assertEq(strategy.balanceOfWant(), 0);
        assertEq(IERC20(AERO).allowance(address(strategy), address(swapper)), 0);
        assertEq(IERC20(PAIR).allowance(address(strategy), GAUGE), 0);
        assertEq(IERC20(AERO).allowance(address(strategy), ROUTER), 0);
        assertEq(IERC20(USDC).allowance(address(strategy), ROUTER), 0);
        assertEq(strategy.lastHarvest(), block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(StrategyAero.ActionLocked.selector, strategy.actionableBlock()));
        strategy.harvest();
        vm.roll(strategy.actionableBlock());
        deal(AERO, address(strategy), 100 ether);
        uint256 before = strategy.balanceOfPool();
        strategy.harvest(address(0xCA11));
        assertGt(strategy.balanceOfPool(), before);
    }

    function testLivePanicExitsDuringPenaltyWindow() public {
        _enablePenalty();
        uint256 lp = _mintLp(address(strategy));
        strategy.deposit();
        assertFalse(strategy.actionable());
        strategy.panic();
        assertTrue(strategy.paused());
        assertEq(strategy.balanceOfPool(), 0);
        assertEq(strategy.balanceOfWant(), lp);
        strategy.withdraw(lp);
        assertEq(IERC20(PAIR).balanceOf(address(this)), lp);
    }

    function testLiveZeroPenaltyAllowsImmediateWithdrawal() public {
        vm.mockCall(
            IAeroGauge(GAUGE).gaugeFactory(),
            abi.encodeWithSelector(IAeroGaugeFactory.effectivePenaltyConfig.selector, GAUGE),
            abi.encode(IAeroGaugeFactory.PenaltyConfig(0, 1e6))
        );
        uint256 lp = _mintLp(address(strategy));
        strategy.deposit();
        assertTrue(strategy.actionable());
        strategy.setWithdrawalFee(0);
        strategy.withdraw(lp);
        assertEq(strategy.balanceOfPool(), 0);
        assertEq(IERC20(PAIR).balanceOf(address(this)), lp);
    }

    function testLiveStablePoolHarvestUsesRealMetarouterAndGauge() public {
        // Registered stable WETH/ETH-derivative pool; different reserve values
        // ensure the stable split is exercised rather than a 50/50 shortcut.
        address stablePool = 0x45ADCE4be5f602273c6E883a4C94133309aF1D09;
        address stableGauge =
            IAeroFactoryRegistry(IAeroRouter(payable(ROUTER)).FACTORY_REGISTRY()).targetToGauge(stablePool);
        assertEq(IAeroPair(stablePool).POOL_TYPE(), bytes32("V2_STABLE"));
        assertTrue(stableGauge != address(0));
        address t0 = IAeroPair(stablePool).token0();
        address t1 = IAeroPair(stablePool).token1();
        AeroTestSwapper quotedSwapper = new AeroTestSwapper();
        // Deterministic funded swaps isolate the stable split and real mint;
        // the volatile fork test separately executes genuine pool swaps.
        quotedSwapper.setRate(AERO, USDC, 1e6);
        quotedSwapper.setRate(USDC, t0, 1e26);
        quotedSwapper.setRate(USDC, t1, 1e26);
        deal(t0, address(quotedSwapper), 1 ether);
        deal(t1, address(quotedSwapper), 1 ether);
        deal(USDC, address(quotedSwapper), 100e6);
        AeroTestHarness s = new AeroTestHarness();
        s.initialize(
            stablePool,
            stableGauge,
            AERO,
            USDC,
            ROUTER,
            false,
            StratFeeManagerInitializable.CommonAddresses(
                address(this), address(quotedSwapper), address(this), address(0x570A7), address(0xBEEF), address(fees)
            )
        );
        assertTrue(s.stable());
        (uint256 a0, uint256 a1) = s.liquiditySplit(90 ether);
        (uint256 r0, uint256 r1,) = IAeroPair(stablePool).getReserves();
        assertApproxEqRel(a0, uint256(90 ether) * r0 / (r0 + r1), 1e12);
        assertEq(a0 + a1, 90 ether);
        deal(AERO, address(s), 100 ether);
        s.harvest(address(0xCA11));
        assertGt(s.balanceOfPool(), 0);
        assertEq(s.balanceOfWant(), 0);
        assertEq(IERC20(t0).allowance(address(s), ROUTER), 0);
        assertEq(IERC20(t1).allowance(address(s), ROUTER), 0);
        // The intermediary has six decimals, so its split can leave more
        // than a few wei of 18-decimal LP tokens after proportional funding.
        assertLt(IERC20(t0).balanceOf(address(s)), 1e10);
        assertLt(IERC20(t1).balanceOf(address(s)), 1e10);
    }

    /// @dev The live factory can disable penalties. Mock only its policy read
    ///      to exercise the lock against the real gauge's deposit/withdraw code.
    function _enablePenalty() private {
        vm.mockCall(
            IAeroGauge(GAUGE).gaugeFactory(),
            abi.encodeWithSelector(IAeroGaugeFactory.effectivePenaltyConfig.selector, GAUGE),
            abi.encode(IAeroGaugeFactory.PenaltyConfig(7, 1e6))
        );
    }
}

/// @notice Exercises the actual OP Beefy routes and Aero stable gauge together.
contract StrategyAeroOptimismForkTest is Test {
    address private constant XAERO = 0xbdEaeA5205d16f34Cb40038052d91235D87B4C54;
    address private constant WETH = 0x4200000000000000000000000000000000000006;
    address private constant ALETH = 0x3E29D3A9316dAB217754d13b28646B76607c5f04;
    address private constant PAIR = 0x98BeB54c7F46514C9045D9d2B9221F52611dDfED;
    address private constant GAUGE = 0x988511ea49A3Cc7e0D6eF36f500b0f72f6A30df7;
    address private constant ROUTER = 0x0fEf9e88A7b76BCDBF451780C6774FE32965Ee98;
    address private constant SWAPPER = 0xe115b50c52cB5624fD76232cDF498ADA6ECD1e69;

    function testHarvestViaWethWithLiveBeefyRoutes() public {
        vm.createSelectFork(vm.envOr("OPTIMISM_RPC", string("https://mainnet.optimism.io")));
        AeroTestFeeConfig fees = new AeroTestFeeConfig();
        StrategyAero strategy = new StrategyAero();
        strategy.initialize(
            PAIR,
            GAUGE,
            XAERO,
            WETH,
            ROUTER,
            false,
            StratFeeManagerInitializable.CommonAddresses(
                address(this), SWAPPER, address(this), address(0x570A7), address(0xBEEF), address(fees)
            )
        );
        // Make a direct xAERO -> alETH swap revert even if one is configured.
        bytes4 swapSelector = bytes4(keccak256("swap(address,address,uint256)"));
        vm.mockCallRevert(SWAPPER, abi.encodePacked(swapSelector, abi.encode(XAERO, ALETH)), bytes("direct route"));
        vm.expectCall(SWAPPER, abi.encodePacked(swapSelector, abi.encode(XAERO, WETH)));
        vm.expectCall(SWAPPER, abi.encodePacked(swapSelector, abi.encode(WETH, ALETH)));
        // Keep the sample small relative to current xAERO route liquidity;
        // the live Beefy Swapper enforces oracle-based slippage protection.
        deal(XAERO, address(strategy), 1 ether);
        uint256 callBefore = IERC20(WETH).balanceOf(address(this));
        strategy.harvest(address(this));
        assertGt(IERC20(WETH).balanceOf(address(this)), callBefore);
        assertGt(strategy.balanceOfPool(), 0);
        assertEq(IERC20(XAERO).allowance(address(strategy), SWAPPER), 0);
        assertEq(IERC20(WETH).allowance(address(strategy), SWAPPER), 0);
        assertEq(IERC20(ALETH).allowance(address(strategy), ROUTER), 0);
        assertEq(IERC20(WETH).allowance(address(strategy), ROUTER), 0);
    }
}
