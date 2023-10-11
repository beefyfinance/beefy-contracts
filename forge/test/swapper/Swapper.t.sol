// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { UniswapV3Utils, IUniswapRouterV3WithDeadline } from "../../../contracts/BIFI/utils/UniswapV3Utils.sol";
import { IUniswapRouterETH } from "../../../contracts/BIFI/interfaces/common/IUniswapRouterETH.sol";
import { ISolidlyRouter } from "../../../contracts/BIFI/interfaces/common/ISolidlyRouter.sol";
import { IBalancerVault } from "../../../contracts/BIFI/interfaces/beethovenx/IBalancerVault.sol";

// Interfaces
import { IERC20 } from "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import { BeefySwapper } from "../../../contracts/BIFI/infra/BeefySwapper.sol";
import { BeefyOracle } from "../../../contracts/BIFI/infra/BeefyOracle/BeefyOracle.sol";
import { BeefyOracleChainlink } from "../../../contracts/BIFI/infra/BeefyOracle/BeefyOracleChainlink.sol";

contract Swapper is Test {

    BeefySwapper public swapper;
    BeefyOracle public oracle;

    address eth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address matic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address usdr = 0x40379a439D4F6795B6fc9aa5687dB461677A2dBa;

    address ethFeedAddress = 0xF9680D99D6C9589e2a93a78A04A279e509205945;
    address usdcFeedAddress = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;
    address maticFeedAddress = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;

    address usdcUsdrSolidlyPool = 0xD17cb0f162f133e339C0BbFc18c36c357E681D6b;

    bytes32 usdcEthBalancerPool = 0x03cd191f589d12b0582a99808cf19851e468e6b500010000000000000000000a;

    address uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address uniswapV2Router = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    address solidlyRouter = 0x06374F57991CDc836E5A318569A910FE6456D230;
    address balancerRouter = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    
    bytes ethFeed = abi.encode(ethFeedAddress);
    bytes usdcFeed = abi.encode(usdcFeedAddress);
    bytes maticFeed = abi.encode(maticFeedAddress);

    address alice;

    function setUp() public {
        oracle = new BeefyOracle();
        oracle.initialize();

        swapper = new BeefySwapper();
        swapper.initialize(address(oracle), 0.99 ether);

        address chainlinkOracle = deployCode("BeefyOracleChainlink.sol");
        oracle.setOracle(eth, chainlinkOracle, ethFeed);
        oracle.setOracle(usdc, chainlinkOracle, usdcFeed);
        oracle.setOracle(matic, chainlinkOracle, maticFeed);

        address[] memory tokens = new address[](2);
        (tokens[0], tokens[1]) = (usdc, usdr);
        address[] memory pools = new address[](1);
        pools[0] = usdcUsdrSolidlyPool;
        uint256[] memory twaps = new uint256[](1);
        twaps[0] = 4;
        bytes memory usdcUsdrSolidlyFeed = abi.encode(tokens, pools, twaps);
        address solidlyOracle = deployCode("BeefyOracleSolidly.sol");
        oracle.setOracle(usdr, solidlyOracle, usdcUsdrSolidlyFeed);

        alice = makeAddr("alice");
        deal(usdc, alice, 1_000_000 * 10 ** 6);
        vm.prank(alice);
        IERC20(usdc).approve(address(swapper), type(uint256).max);
    }

    function testSetSwapInfo() external {
        address[] memory route = new address[](2);
        (route[0], route[1]) = (usdc, eth);
        uint24[] memory fees = new uint24[](1);
        fees[0] = 500;

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
            BeefySwapper.SwapInfo(uniswapV3Router, data, amountIndex, minIndex, minSign)
        );

        vm.prank(alice);
        uint256 ethReceived = swapper.swap(usdc, eth, 1000 * 10 ** 6);
        console.log("ETH received:", ethReceived);
        assertGt(ethReceived, 0, "No ETH received from swap");
    }

    function testSetLongUniswapV3() external {
        address[] memory route = new address[](3);
        (route[0], route[1], route[2]) = (usdc, eth, matic);
        uint24[] memory fees = new uint24[](2);
        (fees[0], fees[1]) = (500, 3000);

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
            BeefySwapper.SwapInfo(uniswapV3Router, data, amountIndex, minIndex, minSign)
        );

        vm.prank(alice);
        uint256 maticReceived = swapper.swap(usdc, matic, 1000 * 10 ** 6);
        console.log("MATIC received:", maticReceived);
        assertGt(maticReceived, 0, "No MATIC received from swap");
    }

    function testSetSwapInfoUniswapV2() external {
        address[] memory route = new address[](2);
        (route[0], route[1]) = (usdc, eth);

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
            BeefySwapper.SwapInfo(uniswapV2Router, data, amountIndex, minIndex, minSign)
        );

        vm.prank(alice);
        uint256 ethReceived = swapper.swap(usdc, eth, 1000 * 10 ** 6);
        console.log("ETH received:", ethReceived);
        assertGt(ethReceived, 0, "No ETH received from swap");
    }

    function testSetSwapInfoSolidly() external {
        address[] memory route = new address[](2);
        (route[0], route[1]) = (usdc, usdr);

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
            BeefySwapper.SwapInfo(solidlyRouter, data, amountIndex, minIndex, minSign)
        );

        vm.prank(alice);
        uint256 usdrReceived = swapper.swap(usdc, usdr, 1000 * 10 ** 6);
        console.log("USDR received:", usdrReceived);
        assertGt(usdrReceived, 0, "No USDR received from swap");
    }

    function testSetSwapInfoBalancer() external {
        uint8 swapKind = 0;
        IBalancerVault.BatchSwapStep[] memory swapSteps = new IBalancerVault.BatchSwapStep[](1);
        swapSteps[0] = IBalancerVault.BatchSwapStep(usdcEthBalancerPool, 0, 1, 0, bytes(""));
        address[] memory assets = new address[](2);
        (assets[0], assets[1]) = (usdc, eth);
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
        int8 minSign = -1;

        swapper.setSwapInfo(
            assets[0],
            assets[assets.length - 1],
            BeefySwapper.SwapInfo(balancerRouter, data, amountIndex, minIndex, minSign)
        );

        vm.prank(alice);
        uint256 ethReceived = swapper.swap(usdc, eth, 1000 * 10 ** 6);
        console.log("ETH received:", ethReceived);
        assertGt(ethReceived, 0, "No ETH received from swap");
    }
}
