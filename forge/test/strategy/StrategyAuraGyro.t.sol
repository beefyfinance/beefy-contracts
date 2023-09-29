//import "forge-std/Test.sol";
pragma solidity ^0.8.0;

import "../../../node_modules/forge-std/src/Test.sol";

import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/strategies/Balancer/StrategyAuraGyroMainnet.sol";
import "../../../contracts/BIFI/strategies/Balancer/BeefyBalancerStructs.sol";
import "../../../contracts/BIFI/strategies/Common/StratFeeManager.sol";

contract StrategyAuraGyroTest is Test {

    BeefyVaultV7 vault;
    StrategyAuraGyroMainnet strategy;

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

    address want = 0xf01b0684C98CD7aDA480BFDF6e43876422fa1Fc1;
    address lp0 = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address lp1 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address booster = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    address router = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address bal = 0xba100000625a3754423978a60c9317c58a424e3D;
    address aura = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;

    uint256 pid = 162;

    error PPFS_NOT_INCREASED();

    function routes() public view returns (
        BeefyBalancerStructs.BatchSwapStruct[] memory _outputToNativeRoute,
        BeefyBalancerStructs.BatchSwapStruct[] memory _nativeToLp0Route,
        BeefyBalancerStructs.BatchSwapStruct[] memory _lp0ToLp1Route,
        BeefyBalancerStructs.BatchSwapStruct[] memory _auraToNativeRoute,
        address[] memory _outputToNativeAssests,
        address[] memory _nativeToLp0Assests,
        address[] memory _lp0ToLp1Assests,
        address[] memory _auraToNativeAssests
    ) {
        _outputToNativeRoute = new BeefyBalancerStructs.BatchSwapStruct[](1);
        _outputToNativeRoute[0] = BeefyBalancerStructs.BatchSwapStruct({
            poolId: 0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014,
            assetInIndex: 0,
            assetOutIndex: 1
        });

        _nativeToLp0Route = new BeefyBalancerStructs.BatchSwapStruct[](1);
        _nativeToLp0Route[0] = BeefyBalancerStructs.BatchSwapStruct({
            poolId: 0x93d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c2,
            assetInIndex: 0,
            assetOutIndex: 1
        });

        _lp0ToLp1Route = new BeefyBalancerStructs.BatchSwapStruct[](1);
        _lp0ToLp1Route[0] = BeefyBalancerStructs.BatchSwapStruct({
            poolId: 0x93d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c2,
            assetInIndex: 0,
            assetOutIndex: 1
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

        _nativeToLp0Assests = new address[](2);
        _nativeToLp0Assests[0] = native;
        _nativeToLp0Assests[1] = lp0;

        _lp0ToLp1Assests = new address[](2);
        _lp0ToLp1Assests[0] = lp0;
        _lp0ToLp1Assests[1] = lp1;

        _auraToNativeAssests = new address[](2);
        _auraToNativeAssests[0] = aura;
        _auraToNativeAssests[1] = native;
    }

    function setUp() public {
        vault = new BeefyVaultV7();
        strategy = new StrategyAuraGyroMainnet();

        (
            BeefyBalancerStructs.BatchSwapStruct[] memory _outputToNativeRoute,
            BeefyBalancerStructs.BatchSwapStruct[] memory _nativeToLp0Route,
            BeefyBalancerStructs.BatchSwapStruct[] memory _lp0ToLp1Route,
            BeefyBalancerStructs.BatchSwapStruct[] memory _auraToNativeRoute,
            address[] memory _outputToNativeAssests,
            address[] memory _nativeToLp0Assests,
            address[] memory _lp0ToLp1Assests,
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
            _nativeToLp0Route,
            _lp0ToLp1Route,
            _outputToNativeRoute,
            booster,
            pid,
            _nativeToLp0Assests,
            _lp0ToLp1Assests,
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
