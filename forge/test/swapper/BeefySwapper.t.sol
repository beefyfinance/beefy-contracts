// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {BeefyOracle} from "../../../contracts/BIFI/infra/BeefyOracle/BeefyOracle.sol";
import {BeefySwapper} from "../../../contracts/BIFI/infra/BeefySwapper.sol";
import {IBeefySwapper} from "../../../contracts/BIFI/interfaces/beefy/IBeefySwapper.sol";
import {IBalancerVault} from "../../../contracts/BIFI/interfaces/beethovenx/IBalancerVault.sol";
import {ISolidlyRouter} from "../../../contracts/BIFI/interfaces/common/ISolidlyRouter.sol";
import {IUniswapRouterETH} from "../../../contracts/BIFI/interfaces/common/IUniswapRouterETH.sol";
import {IUniswapRouterV3WithDeadline} from "../../../contracts/BIFI/interfaces/common/IUniswapRouterV3WithDeadline.sol";
import {UniswapV3Utils} from "../../../contracts/BIFI/utils/UniswapV3Utils.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

// need to do fork test on polygon at a block where there is still USDR liquidity on Pearl
// forge test --match-contract BeefySwapperTest --rpc-url polygon --fork-block-number 45899195
contract BeefySwapperTest is Test {
    address private constant eth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address private constant usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address private constant matic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address private constant usdr = 0x40379a439D4F6795B6fc9aa5687dB461677A2dBa;
    address private constant bnb = 0x3BA4c387f786bFEE076A58914F5Bd38d668B42c3;

    address private constant ethFeedAddress = 0xF9680D99D6C9589e2a93a78A04A279e509205945;
    address private constant usdcFeedAddress = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;
    address private constant maticFeedAddress = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;

    address private constant usdcUsdrSolidlyPool = 0xD17cb0f162f133e339C0BbFc18c36c357E681D6b;

    bytes32 private constant usdcEthBalancerPool = 0x03cd191f589d12b0582a99808cf19851e468e6b500010000000000000000000a;

    address private constant uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniswapV2Router = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    address private constant solidlyRouter = 0x06374F57991CDc836E5A318569A910FE6456D230;
    address private constant balancerRouter = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    bytes private constant ethFeed = abi.encode(ethFeedAddress);
    bytes private constant usdcFeed = abi.encode(usdcFeedAddress);
    bytes private constant maticFeed = abi.encode(maticFeedAddress);

    BeefySwapper private swapper;
    BeefyOracle private oracle;
    address private alice;

    function setUp() public {
        oracle = setUpOracle();
        swapper = setUpSwapper(address(oracle));
        alice = setUpUser("alice", address(swapper));
    }

    function setUpOracle() internal returns (BeefyOracle _oracle) {
        _oracle = new BeefyOracle();
        _oracle.initialize();

        address chainlinkOracle = deployCode("BeefyOracleChainlink.sol");
        _oracle.setOracle(eth, chainlinkOracle, ethFeed);
        _oracle.setOracle(usdc, chainlinkOracle, usdcFeed);
        _oracle.setOracle(matic, chainlinkOracle, maticFeed);

        address[] memory tokens = new address[](2);
        (tokens[0], tokens[1]) = (usdc, usdr);
        address[] memory pools = new address[](1);
        pools[0] = usdcUsdrSolidlyPool;
        uint256[] memory twaps = new uint256[](1);
        twaps[0] = 4;
        bytes memory usdcUsdrSolidlyFeed = abi.encode(tokens, pools, twaps);
        address solidlyOracle = deployCode("BeefyOracleSolidly.sol");
        _oracle.setOracle(usdr, solidlyOracle, usdcUsdrSolidlyFeed);
    }

    function setUpSwapper(address _oracle) internal returns (BeefySwapper _swapper) {
        _swapper = new BeefySwapper();
        _swapper.initialize(_oracle, 0.99 ether);
    }

    function setUpUser(string memory _name, address _swapper) internal returns (address _user) {
        _user = makeAddr(_name);
        vm.startPrank(_user);
        IERC20MetadataUpgradeable(usdc).approve(_swapper, type(uint256).max);
        IERC20MetadataUpgradeable(eth).approve(_swapper, type(uint256).max);
        IERC20MetadataUpgradeable(matic).approve(_swapper, type(uint256).max);
        vm.stopPrank();
    }

    function setSwapInfoUniswapV3(address _asset0, address _asset1, uint24 _fees0_1, address _router) internal {
        address[] memory route = new address[](2);
        (route[0], route[1]) = (_asset0, _asset1);
        uint24[] memory fees = new uint24[](1);
        fees[0] = _fees0_1;

        bytes memory data = abi.encodeWithSelector(
            IUniswapRouterV3WithDeadline.exactInput.selector,
            IUniswapRouterV3WithDeadline.ExactInputParams(
                UniswapV3Utils.routeToPath(route, fees),
                address(swapper),
                type(uint256).max,
                0,
                0
            )
        );
        uint256 amountIndex = 132;
        uint256 minIndex = 164;
        int8 minSign = 0;

        swapper.setSwapInfo(
            route[0],
            route[route.length - 1],
            IBeefySwapper.SwapInfo(_router, data, amountIndex, minIndex, minSign)
        );
    }

    function setSwapInfoUniswapV3(address _asset0, address _asset1, address _asset2, uint24 _fees0_1, uint24 _fees1_2, address _router) internal {
        address[] memory route = new address[](3);
        (route[0], route[1], route[2]) = (_asset0, _asset1, _asset2);
        uint24[] memory fees = new uint24[](2);
        (fees[0], fees[1]) = (_fees0_1, _fees1_2);

        bytes memory data = abi.encodeWithSelector(
            IUniswapRouterV3WithDeadline.exactInput.selector,
            IUniswapRouterV3WithDeadline.ExactInputParams(
                UniswapV3Utils.routeToPath(route, fees),
                address(swapper),
                type(uint256).max,
                0,
                0
            )
        );
        uint256 amountIndex = 132;
        uint256 minIndex = 164;
        int8 minSign = 0;

        swapper.setSwapInfo(
            route[0],
            route[route.length - 1],
            IBeefySwapper.SwapInfo(_router, data, amountIndex, minIndex, minSign)
        );
    }

    function testSetSwapInfoUniswapV3() external {
        address tokenIn = usdc;
        address tokenOut = eth;
        setSwapInfoUniswapV3(tokenIn, tokenOut, 500, uniswapV3Router);

        uint256 amountIn = getInputAmount(tokenIn, alice);
        vm.prank(alice);
        uint256 received = swapper.swap(tokenIn, tokenOut, amountIn);

        console.log("Received:", received);
        assertGt(received, 0, "Should output > 0");
    }

    function testSetSwapInfoUniswapV3Long() external {
        address tokenIn = usdc;
        address tokenOut = matic;
        setSwapInfoUniswapV3(tokenIn, eth, tokenOut, 500, 3000, uniswapV3Router);

        uint256 amountIn = getInputAmount(tokenIn, alice);
        vm.prank(alice);
        uint256 received = swapper.swap(tokenIn, tokenOut, amountIn);

        console.log("Received:", received);
        assertGt(received, 0, "Should output > 0");
    }

    function setSwapInfoUniswapV2(address _asset0, address _asset1, address _router) internal {
        address[] memory route = new address[](2);
        (route[0], route[1]) = (_asset0, _asset1);

        bytes memory data = abi.encodeWithSelector(
            IUniswapRouterETH.swapExactTokensForTokens.selector,
            0,
            0,
            route,
            address(swapper),
            type(uint256).max
        );
        uint256 amountIndex = 4;
        uint256 minIndex = 36;
        int8 minSign = 0;

        swapper.setSwapInfo(
            route[0],
            route[route.length - 1],
            IBeefySwapper.SwapInfo(_router, data, amountIndex, minIndex, minSign)
        );
    }

    function testSetSwapInfoUniswapV2() external {
        address tokenIn = usdc;
        address tokenOut = eth;
        setSwapInfoUniswapV2(tokenIn, tokenOut, uniswapV2Router);

        uint256 amountIn = getInputAmount(tokenIn, alice);
        vm.prank(alice);
        uint256 received = swapper.swap(tokenIn, tokenOut, amountIn);

        console.log("Received:", received);
        assertGt(received, 0, "Should output > 0");
    }

    function setSwapInfoSolidly(address _asset0, address _asset1, address _router) internal {
        address[] memory route = new address[](2);
        (route[0], route[1]) = (_asset0, _asset1);

        ISolidlyRouter.Routes[] memory path = new ISolidlyRouter.Routes[](1);
        path[0] = ISolidlyRouter.Routes(route[0], route[1], true);

        bytes memory data = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,(address,address,bool)[],address,uint256)",
            0,
            0,
            path,
            address(swapper),
            type(uint256).max
        );
        uint256 amountIndex = 4;
        uint256 minIndex = 36;
        int8 minSign = 0;

        swapper.setSwapInfo(
            route[0],
            route[route.length - 1],
            IBeefySwapper.SwapInfo(_router, data, amountIndex, minIndex, minSign)
        );
    }

    function testSetSwapInfoSolidly() external {
        address tokenIn = usdc;
        address tokenOut = usdr;
        setSwapInfoSolidly(tokenIn, tokenOut, solidlyRouter);

        uint256 amountIn = getInputAmount(tokenIn, alice);
        vm.prank(alice);
        uint256 received = swapper.swap(tokenIn, tokenOut, amountIn);

        console.log("Received:", received);
        assertGt(received, 0, "Should output > 0");
    }

    function setSwapInfoBalancer(address _asset0, address _asset1, bytes32 _poolId, address _router) internal {
        uint8 swapKind = 0;
        IBalancerVault.BatchSwapStep[] memory swapSteps = new IBalancerVault.BatchSwapStep[](1);
        swapSteps[0] = IBalancerVault.BatchSwapStep(_poolId, 0, 1, 0, bytes(""));
        address[] memory assets = new address[](2);
        (assets[0], assets[1]) = (_asset0, _asset1);
        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement(
            address(swapper), false, payable(address(swapper)), false
        );
        int256[] memory limits = new int256[](2);
        (limits[0], limits[1]) = (type(int256).max, 0);

        bytes memory data = abi.encodeWithSelector(
            IBalancerVault.batchSwap.selector,
            swapKind,
            swapSteps,
            assets,
            funds,
            limits,
            type(uint256).max
        );
        uint256 amountIndex = 452;
        uint256 minIndex = 708;
        int8 minSign = - 1;

        swapper.setSwapInfo(
            assets[0],
            assets[assets.length - 1],
            IBeefySwapper.SwapInfo(_router, data, amountIndex, minIndex, minSign)
        );
    }

    function testSetSwapInfoBalancer() external {
        address tokenIn = usdc;
        address tokenOut = eth;
        setSwapInfoBalancer(tokenIn, tokenOut, usdcEthBalancerPool, balancerRouter);

        uint256 amountIn = getInputAmount(tokenIn, alice);
        vm.prank(alice);
        uint256 received = swapper.swap(tokenIn, tokenOut, amountIn);

        console.log("Received:", received);
        assertGt(received, 0, "Should output > 0");
    }

    function getInputAmount(address _token, address _user) internal returns (uint256 _amountIn) {
        _amountIn = (_token == eth ? 1 : 1000) * 10 ** IERC20MetadataUpgradeable(_token).decimals();
        deal(_token, _user, _amountIn);
    }

    function testManualRouteSwapUsdcRouteTooShort() external {
        setSwapInfoUniswapV2(usdc, eth, uniswapV2Router);

        address[] memory route = new address[](1);
        route[0] = usdc;

        uint256 amountIn = getInputAmount(route[0], alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BeefySwapper.RouteTooShort.selector, 2));
        swapper.swap(route, amountIn);
    }

    function testManualRouteSwapUsdcEth() external {
        setSwapInfoUniswapV2(usdc, eth, uniswapV2Router);

        address[] memory route = new address[](2);
        (route[0], route[1]) = (usdc, eth);

        uint256 amountIn = getInputAmount(route[0], alice);
        vm.prank(alice);
        uint256 received = swapper.swap(route, amountIn);

        console.log("Received:", received);
        assertGt(received, 0, "Should output > 0");
    }

    function testManualRouteSwapEthUsdc() external {
        setSwapInfoUniswapV2(eth, usdc, uniswapV2Router);

        address[] memory route = new address[](2);
        (route[0], route[1]) = (eth, usdc);

        uint256 amountIn = getInputAmount(route[0], alice);
        vm.prank(alice);
        uint256 received = swapper.swap(route, amountIn);

        console.log("Received:", received);
        assertGt(received, 0, "Should output > 0");
    }

    function testManualRouteSwapUsdcEthMatic() external {
        setSwapInfoUniswapV2(usdc, eth, uniswapV2Router);
        setSwapInfoUniswapV3(eth, matic, 3000, uniswapV3Router);

        address[] memory route = new address[](3);
        (route[0], route[1], route[2]) = (usdc, eth, matic);

        uint256 amountIn = getInputAmount(route[0], alice);
        vm.prank(alice);
        uint256 received = swapper.swap(route, amountIn);

        console.log("Received:", received);
        assertGt(received, 0, "Should output > 0");
    }

    function testManualRouteSwapMaticEthUsdc() external {
        setSwapInfoUniswapV3(matic, eth, 3000, uniswapV3Router);
        setSwapInfoUniswapV2(eth, usdc, uniswapV2Router);

        address[] memory route = new address[](3);
        (route[0], route[1], route[2]) = (matic, eth, usdc);

        uint256 amountIn = getInputAmount(route[0], alice);
        vm.prank(alice);
        uint256 received = swapper.swap(route, amountIn);

        console.log("Received:", received);
        assertGt(received, 0, "Should output > 0");
    }

    function testManualRouteSwapUsdcEthMaticSlippage() external {
        setSwapInfoUniswapV2(usdc, eth, uniswapV2Router);
        setSwapInfoUniswapV3(eth, matic, 3000, uniswapV3Router);

        address[] memory route = new address[](3);
        (route[0], route[1], route[2]) = (usdc, eth, matic);

        uint256 amountIn = getInputAmount(route[0], alice);
        uint256 expectedAmountOut = swapper.getAmountOut(route[0], route[2], amountIn);
        uint256 minAmountOut = expectedAmountOut * 101 / 100; // 1% more than expected

        vm.prank(alice);
        vm.expectPartialRevert(BeefySwapper.SwapFailed.selector); // only check selector, not data
        swapper.swap(route, amountIn, minAmountOut);
    }

    function testSavedRouteSwapUsdcEthMatic() external {
        setSwapInfoUniswapV2(usdc, eth, uniswapV2Router);
        setSwapInfoUniswapV3(eth, matic, 3000, uniswapV3Router);

        address[] memory route = new address[](3);
        (route[0], route[1], route[2]) = (usdc, eth, matic);
        swapper.setSwapRoute(route);

        uint256 amountIn = getInputAmount(route[0], alice);
        vm.prank(alice);
        uint256 received = swapper.swap(route[0], route[2], amountIn);

        console.log("Received:", received);
        assertGt(received, 0, "Should output > 0");
    }

    function testSetSwapRouteTooShort() external {
        address[] memory route = new address[](2);
        (route[0], route[1]) = (eth, usdc);

        vm.expectRevert(abi.encodeWithSelector(BeefySwapper.RouteTooShort.selector, 3));
        swapper.setSwapRoute(route);
    }

    function testSetSwapRouteNoOracle() external {
        address[] memory route = new address[](3);
        (route[0], route[1], route[2]) = (eth, usdc, bnb);

        // oracle is throwing rather than returning success=false so can't target PriceFailed
        //vm.expectRevert(abi.encodeWithSelector(BeefySwapper.PriceFailed.selector, bnb));
        vm.expectRevert();
        swapper.setSwapRoute(route);
    }

    function testSetSwapRouteNoSwapData() external {
        setSwapInfoUniswapV2(usdc, eth, uniswapV2Router);
        //setSwapInfoUniswapV3(eth, matic, 3000, uniswapV3Router);

        address[] memory route = new address[](3);
        (route[0], route[1], route[2]) = (usdc, eth, matic);

        vm.expectRevert(abi.encodeWithSelector(BeefySwapper.NoSwapData.selector, eth, matic));
        swapper.setSwapRoute(route);
    }

    function testSetSwapRouteTwice() external {
        setSwapInfoUniswapV2(usdc, eth, uniswapV2Router);
        setSwapInfoUniswapV2(eth, usdc, uniswapV2Router);
        setSwapInfoUniswapV3(eth, matic, 3000, uniswapV3Router);

        address[] memory route = new address[](5);
        (route[0], route[1], route[2], route[3], route[4]) = (usdc, eth, usdc, eth, matic);
        swapper.setSwapRoute(route);

        uint256 amountIn = getInputAmount(route[0], alice);
        vm.prank(alice);
        uint256 received = swapper.swap(route[0], route[4], amountIn, 0); // fails slippage otherwise

        console.log("Received:", received);
        assertGt(received, 0, "Should output > 0");

        address[] memory routeShorter = new address[](3);
        (routeShorter[0], routeShorter[1], routeShorter[2]) = (usdc, eth, matic);
        swapper.setSwapRoute(routeShorter);

        uint256 amountInShorter = getInputAmount(routeShorter[0], alice);
        vm.prank(alice);
        uint256 receivedShorter = swapper.swap(routeShorter[0], routeShorter[2], amountInShorter, 0);

        console.log("Received (Shorter):", receivedShorter);
        assertGt(receivedShorter, received, "Should output more than the longer route");
    }
}
