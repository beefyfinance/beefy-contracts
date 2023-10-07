//import "forge-std/Test.sol";
pragma solidity ^0.8.0;

import "../../../node_modules/forge-std/src/Test.sol";

import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/strategies/Balancer/StrategyAuraMainnet.sol";
import "../../../contracts/BIFI/strategies/Balancer/BeefyBalancerStructs.sol";
import "../../../contracts/BIFI/strategies/Common/StratFeeManager.sol";

contract StrategyAuraMainnetTest is Test {

    BeefyVaultV7 vault;
    StrategyAuraMainnet strategy;

    struct CommonAddresses {
        address vault;
        address unirouter;
        address keeper;
        address strategist;
        address beefyFeeRecipient;
        address beefyFeeConfig;
    }

    address user = 0x161D61e30284A33Ab1ed227beDcac6014877B3DE;
    address keeper = 0x4fED5491693007f0CD49f4614FFC38Ab6A04B619;
    address feeRecipient = 0x8237f3992526036787E8178Def36291Ab94638CD;
    address feeConfig = 0x3d38BA27974410679afF73abD096D7Ba58870EAd;

    address want = 0x8353157092ED8Be69a9DF8F95af097bbF33Cb2aF;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address booster = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    address router = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address bal = 0xba100000625a3754423978a60c9317c58a424e3D;
    address aura = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;

    uint256 pid = 157;
    bool inputIsComposable = true;
    bool composable = true;

    error PPFS_NOT_INCREASED();

    function routes() public view returns (
        BeefyBalancerStructs.BatchSwapStruct[] memory _outputToNativeRoute,
        BeefyBalancerStructs.BatchSwapStruct[] memory _nativeToInputRoute,
        BeefyBalancerStructs.BatchSwapStruct[] memory _auraToNativeRoute,
        address[] memory _outputToNativeAssests,
        address[] memory _nativeToInputAssests,
        address[] memory _auraToNativeAssests
    ) {
        _outputToNativeRoute = new BeefyBalancerStructs.BatchSwapStruct[](1);
        _outputToNativeRoute[0] = BeefyBalancerStructs.BatchSwapStruct({
            poolId: 0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014,
            assetInIndex: 0,
            assetOutIndex: 1
        });

        _nativeToInputRoute = new BeefyBalancerStructs.BatchSwapStruct[](2);
        _nativeToInputRoute[0] = BeefyBalancerStructs.BatchSwapStruct({
            poolId: 0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019,
            assetInIndex: 0,
            assetOutIndex: 1
        });
        _nativeToInputRoute[1] = BeefyBalancerStructs.BatchSwapStruct({
            poolId: 0x8353157092ed8be69a9df8f95af097bbf33cb2af0000000000000000000005d9,
            assetInIndex: 1,
            assetOutIndex: 2
        });

        _auraToNativeRoute = new BeefyBalancerStructs.BatchSwapStruct[](1);
        _auraToNativeRoute[0] = BeefyBalancerStructs.BatchSwapStruct({
            poolId: 0xc29562b045d80fd77c69bec09541f5c16fe20d9d000200000000000000000251,
            assetInIndex: 0,
            assetOutIndex: 1
        });

        _outputToNativeAssests = new address[](2);
        _outputToNativeAssests[0] = bal;
        _outputToNativeAssests[1] = native;

        _nativeToInputAssests = new address[](3);
        _nativeToInputAssests[0] = native;
        _nativeToInputAssests[1] = usdc;
        _nativeToInputAssests[2] = want;

        _auraToNativeAssests = new address[](2);
        _auraToNativeAssests[0] = aura;
        _auraToNativeAssests[1] = native;
    }

    function setUp() public {
        vault = new BeefyVaultV7();
        strategy = new StrategyAuraMainnet();

        (
            BeefyBalancerStructs.BatchSwapStruct[] memory _outputToNativeRoute,
            BeefyBalancerStructs.BatchSwapStruct[] memory _nativeToInputRoute,
            BeefyBalancerStructs.BatchSwapStruct[] memory _auraToNativeRoute,
            address[] memory _outputToNativeAssests,
            address[] memory _nativeToInputAssests,
            address[] memory _auraToNativeAssests
        ) = routes();   

        StratFeeManagerInitializable.CommonAddresses memory commonAddresses = StratFeeManagerInitializable.CommonAddresses({
            vault: address(vault),
            unirouter: router,
            keeper: keeper,
            strategist: user,
            beefyFeeRecipient: feeRecipient,
            beefyFeeConfig: feeConfig
        });

        vault.initialize(IStrategyV7(address(strategy)), "MooTest", "mooTest", 0);
        strategy.initialize(
            want,
            inputIsComposable,
            _nativeToInputRoute,
            _outputToNativeRoute,
            booster,
            pid,
            composable,
            _nativeToInputAssests,
            _outputToNativeAssests,
            commonAddresses
        );

        strategy.addRewardToken(aura, _auraToNativeRoute, _auraToNativeAssests, bytes("0x"), 0);
        strategy.setWithdrawalFee(0);
    }

    function test_depositAndWithdraw() public {
        vm.startPrank(user);
        
        deal(want, user, 10 ether);

        IERC20(want).approve(address(vault), 10 ether);
        vault.deposit(10 ether);

        assertEq(IERC20(want).balanceOf(address(user)), 0);

        vault.withdraw(10 ether);

        assertEq(IERC20(want).balanceOf(address(user)), 10 ether);
        vm.stopPrank();
    }

    function test_harvest() public {
        vm.startPrank(user);

        deal(want, user, 10 ether);

        IERC20(want).approve(address(vault), 10 ether);
        vault.deposit(10 ether);

        uint256 ppfs = vault.getPricePerFullShare();
        skip(1 days);

        strategy.harvest();

        skip(1 minutes);
        uint256 afterPpfs = vault.getPricePerFullShare();

        if (afterPpfs <= ppfs) revert PPFS_NOT_INCREASED();
        vm.stopPrank();
    }

    function test_panic() public {
        vm.startPrank(user);

        deal(want, user, 10 ether);

        IERC20(want).approve(address(vault), 10 ether);
        vault.deposit(10 ether);

        vm.stopPrank();
        vm.startPrank(keeper);

        strategy.panic();

        vm.stopPrank();
        vm.startPrank(user);

        vault.withdraw(5 ether);

        vm.expectRevert();
        vault.deposit(5 ether);

        vm.stopPrank();

        vm.startPrank(keeper);

        strategy.unpause();

        skip(1 days);

        strategy.harvest(); 

        vm.stopPrank();
    }
}
