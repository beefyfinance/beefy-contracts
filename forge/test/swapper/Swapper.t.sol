// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { UniswapV3Utils, IUniswapRouterV3WithDeadline } from "../../../contracts/BIFI/utils/UniswapV3Utils.sol";

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

    address ethFeedAddress = 0xF9680D99D6C9589e2a93a78A04A279e509205945;
    address usdcFeedAddress = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;
    address maticFeedAddress = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;

    address uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    
    bytes ethFeed = abi.encode(ethFeedAddress);
    bytes usdcFeed = abi.encode(usdcFeedAddress);
    bytes maticFeed = abi.encode(maticFeedAddress);

    function setUp() public {
        oracle = new BeefyOracle();
        oracle.initialize();

        swapper = new BeefySwapper();
        swapper.initialize(address(oracle), 0.99 ether);

        address chainlinkOracle = deployCode("BeefyOracleChainlink.sol");
        oracle.setOracle(eth, chainlinkOracle, ethFeed);
        oracle.setOracle(usdc, chainlinkOracle, usdcFeed);
        oracle.setOracle(matic, chainlinkOracle, maticFeed);
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

        address alice = makeAddr("alice");
        deal(usdc, alice, 1000 * 10 ** 6);
        vm.startPrank(alice);
        IERC20(usdc).approve(address(swapper), 1000 * 10 ** 6);
        uint256 ethReceived = swapper.swap(usdc, eth, 1000 * 10 ** 6);
        console.log(ethReceived);
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

        address alice = makeAddr("alice");
        deal(usdc, alice, 1000 * 10 ** 6);
        vm.startPrank(alice);
        IERC20(usdc).approve(address(swapper), 1000 * 10 ** 6);
        uint256 maticReceived = swapper.swap(usdc, matic, 1000 * 10 ** 6);
        console.log(maticReceived);
        assertGt(maticReceived, 0, "No ETH received from swap");
    }
}
