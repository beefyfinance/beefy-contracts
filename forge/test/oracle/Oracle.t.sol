// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Test.sol";

// Interfaces
import { IERC20 } from "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "../../../contracts/BIFI/interfaces/common/IUniswapV2Pair.sol";
import { IUniswapRouterETH } from "../../../contracts/BIFI/interfaces/common/IUniswapRouterETH.sol";
import { BeefyOracle } from "../../../contracts/BIFI/infra/BeefyOracle/BeefyOracle.sol";
import { BeefyOracleChainlink } from "../../../contracts/BIFI/infra/BeefyOracle/BeefyOracleChainlink.sol";
import { BeefyOracleUniswapV3 } from "../../../contracts/BIFI/infra/BeefyOracle/BeefyOracleUniswapV3.sol";
import { BeefyOracleUniswapV2 } from "../../../contracts/BIFI/infra/BeefyOracle/BeefyOracleUniswapV2.sol";
import { BeefyOracleSolidly } from "../../../contracts/BIFI/infra/BeefyOracle/BeefyOracleSolidly.sol";
import { BeefyOracleErrors } from "../../../contracts/BIFI/infra/BeefyOracle/BeefyOracleErrors.sol";

contract Oracle is Test {

    BeefyOracle public oracle;

    address eth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address matic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address usdr = 0x40379a439D4F6795B6fc9aa5687dB461677A2dBa;

    address ethFeedAddress = 0xF9680D99D6C9589e2a93a78A04A279e509205945;
    address usdcFeedAddress = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;
    address maticFeedAddress = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;

    address usdcEthUniswapV3Pool = 0x45dDa9cb7c25131DF268515131f647d726f50608;
    address ethMaticUniswapV3Pool = 0x86f1d8390222A3691C28938eC7404A1661E618e0;

    address usdcEthUniswapV2Pool = 0x853Ee4b2A13f8a742d64C8F088bE7bA2131f670d;

    address usdcUsdrSolidlyPool = 0xD17cb0f162f133e339C0BbFc18c36c357E681D6b;
    address usdrEthSolidlyPool = 0x74c64d1976157E7Aaeeed46EF04705F4424b27eC;

    address quickRouter = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    
    bytes ethFeed = abi.encode(ethFeedAddress);
    bytes usdcFeed = abi.encode(usdcFeedAddress);
    bytes maticFeed = abi.encode(maticFeedAddress);

    function setUp() public {
        oracle = new BeefyOracle();
        oracle.initialize();
    }

    function testSetChainlinkOracle() external {
        address chainlinkOracle = deployCode("BeefyOracleChainlink.sol");
        oracle.setOracle(eth, chainlinkOracle, ethFeed);

        (uint256 price,) = oracle.getFreshPrice(eth);
        console.log("ETH Price:", price);
        assertGt(price, 0, "ETH price not fetched");
    }

    function testSetUniswapV3Oracle() external {
        address chainlinkOracle = deployCode("BeefyOracleChainlink.sol");
        oracle.setOracle(usdc, chainlinkOracle, usdcFeed);

        address[] memory tokens = new address[](2);
        (tokens[0], tokens[1]) = (usdc, eth);
        address[] memory pools = new address[](1);
        pools[0] = usdcEthUniswapV3Pool;
        uint256[] memory twaps = new uint256[](1);
        twaps[0] = 7200;

        bytes memory usdcEthUniswapV3Feed = abi.encode(tokens, pools, twaps);

        address uniswapV3Oracle = deployCode("BeefyOracleUniswapV3.sol");
        oracle.setOracle(eth, uniswapV3Oracle, usdcEthUniswapV3Feed);

        (uint256 price,) = oracle.getFreshPrice(eth);
        console.log("ETH Price:", price);
        assertGt(price, 0, "ETH price not fetched");
    }

    function testSetUniswapV2Oracle() external {
        address chainlinkOracle = deployCode("BeefyOracleChainlink.sol");
        oracle.setOracle(usdc, chainlinkOracle, usdcFeed);

        address[] memory tokens = new address[](2);
        (tokens[0], tokens[1]) = (usdc, eth);
        address[] memory pairs = new address[](1);
        pairs[0] = usdcEthUniswapV2Pool;
        uint256[] memory twaps = new uint256[](1);
        twaps[0] = 60;

        bytes memory usdcEthUniswapV2Feed = abi.encode(tokens, pairs, twaps);

        IUniswapV2Pair(usdcEthUniswapV2Pool).sync();

        address uniswapV2Oracle = deployCode("BeefyOracleUniswapV2.sol");
        oracle.setOracle(eth, uniswapV2Oracle, usdcEthUniswapV2Feed);
        uint256 startPrice = oracle.getPrice(eth);
        console.log("ETH start price:", startPrice);
        skip(30);

        address alice = makeAddr("alice");
        deal(usdc, alice, 100000 * 10 ** 6);
        vm.startPrank(alice);
        IERC20(usdc).approve(quickRouter, 100000 * 10 ** 6);
        IUniswapRouterETH(quickRouter).swapExactTokensForTokens(
            100000 * 10 ** 6, 0, tokens, alice, block.timestamp
        );

        skip(31);

        (uint256 endPrice,) = oracle.getFreshPrice(eth);
        console.log("ETH end price:", endPrice);
        assertGt(endPrice, startPrice, "ETH price has not increased");
    }

    function testSetSolidlyOracle() external {
        address chainlinkOracle = deployCode("BeefyOracleChainlink.sol");
        oracle.setOracle(usdc, chainlinkOracle, usdcFeed);

        address[] memory tokens = new address[](2);
        (tokens[0], tokens[1]) = (usdc, usdr);
        address[] memory pools = new address[](1);
        pools[0] = usdcUsdrSolidlyPool;
        uint256[] memory twaps = new uint256[](1);
        twaps[0] = 4;

        bytes memory usdcUsdrSolidlyFeed = abi.encode(tokens, pools, twaps);

        (tokens[0], tokens[1]) = (usdr, eth);
        pools[0] = usdrEthSolidlyPool;

        bytes memory usdrEthSolidlyFeed = abi.encode(tokens, pools, twaps);

        address solidlyOracle = deployCode("BeefyOracleSolidly.sol");
        oracle.setOracle(usdr, solidlyOracle, usdcUsdrSolidlyFeed);
        oracle.setOracle(eth, solidlyOracle, usdrEthSolidlyFeed);

        (uint256 usdrPrice,) = oracle.getFreshPrice(usdr);
        console.log("USDR price:", usdrPrice);
        assertGt(usdrPrice, 0, "USDR price not fetched");

        (uint256 ethPrice,) = oracle.getFreshPrice(eth);
        console.log("ETH price:", ethPrice);
        assertGt(ethPrice, 0, "ETH price not fetched");
    }

    function testSetMultipleOracles() external {
        address chainlinkOracle = deployCode("BeefyOracleChainlink.sol");

        address[] memory tokens = new address[](2);
        (tokens[0], tokens[1]) = (eth, usdc);
        address[] memory oracles = new address[](2);
        (oracles[0], oracles[1]) = (chainlinkOracle, chainlinkOracle);
        bytes[] memory feeds = new bytes[](2);
        (feeds[0], feeds[1]) = (ethFeed, usdcFeed);

        oracle.setOracles(tokens, oracles, feeds);

        (uint256 ethPrice,) = oracle.getFreshPrice(eth);
        console.log("ETH price:", ethPrice);
        assertGt(ethPrice, 0, "ETH price not fetched");
        (uint256 usdcPrice,) = oracle.getFreshPrice(usdc);
        console.log("USDC price:", usdcPrice);
        assertGt(usdcPrice, 0, "USDC price not fetched");
    }

    function testSetOracleNoBasePrice() external {
        address[] memory tokens = new address[](2);
        (tokens[0], tokens[1]) = (usdc, eth);
        address[] memory pools = new address[](1);
        pools[0] = usdcEthUniswapV3Pool;
        uint256[] memory twaps = new uint256[](1);
        twaps[0] = 7200;

        bytes memory usdcEthUniswapV3Feed = abi.encode(tokens, pools, twaps);

        address uniswapV3Oracle = deployCode("BeefyOracleUniswapV3.sol");
        vm.expectRevert(abi.encodeWithSelector(BeefyOracleErrors.NoBasePrice.selector, usdc));
        oracle.setOracle(eth, uniswapV3Oracle, usdcEthUniswapV3Feed);
    }

    function testSetOracleNoAnswer() external {
        address chainlinkOracle = deployCode("BeefyOracleChainlink.sol");
        bytes memory emptyFeed = abi.encode(address(0));
        vm.expectRevert();
        oracle.setOracle(eth, chainlinkOracle, emptyFeed);
    }

    function testSetOracleTokenNotInPair() external {
        address chainlinkOracle = deployCode("BeefyOracleChainlink.sol");
        oracle.setOracle(usdc, chainlinkOracle, usdcFeed);

        address[] memory tokens = new address[](2);
        (tokens[0], tokens[1]) = (usdc, matic);
        address[] memory pools = new address[](1);
        pools[0] = usdcEthUniswapV3Pool;
        uint256[] memory twaps = new uint256[](1);
        twaps[0] = 7200;

        bytes memory usdcMaticUniswapV3Feed = abi.encode(tokens, pools, twaps);

        address uniswapV3Oracle = deployCode("BeefyOracleUniswapV3.sol");
        vm.expectRevert();
        oracle.setOracle(matic, uniswapV3Oracle, usdcMaticUniswapV3Feed);
    }

    function testSetChainedUniswapV3Oracles() external {
        address chainlinkOracle = deployCode("BeefyOracleChainlink.sol");
        oracle.setOracle(usdc, chainlinkOracle, usdcFeed);

        address[] memory tokens = new address[](3);
        (tokens[0], tokens[1], tokens[2]) = (usdc, eth, matic);
        address[] memory pools = new address[](2);
        (pools[0], pools[1]) = (usdcEthUniswapV3Pool, ethMaticUniswapV3Pool);
        uint256[] memory twaps = new uint256[](2);
        (twaps[0], twaps[1]) = (7200, 7200);

        bytes memory usdcMaticUniswapV3Feed = abi.encode(tokens, pools, twaps);

        address uniswapV3Oracle = deployCode("BeefyOracleUniswapV3.sol");
        oracle.setOracle(matic, uniswapV3Oracle, usdcMaticUniswapV3Feed);

        (uint256 price,) = oracle.getFreshPrice(matic);
        console.log("MATIC price:", price);
        assertGt(price, 0, "MATIC price not fetched");
    }

    function testOverwriteOracle() external {
        address chainlinkOracle = deployCode("BeefyOracleChainlink.sol");
        oracle.setOracle(usdc, chainlinkOracle, usdcFeed);
        oracle.setOracle(eth, chainlinkOracle, ethFeed);

        address[] memory tokens = new address[](2);
        (tokens[0], tokens[1]) = (usdc, eth);
        address[] memory pools = new address[](1);
        pools[0] = usdcEthUniswapV3Pool;
        uint256[] memory twaps = new uint256[](1);
        twaps[0] = 7200;

        bytes memory usdcEthUniswapV3Feed = abi.encode(tokens, pools, twaps);

        address uniswapV3Oracle = deployCode("BeefyOracleUniswapV3.sol");
        oracle.setOracle(eth, uniswapV3Oracle, usdcEthUniswapV3Feed);
        (uint256 price,) = oracle.getFreshPrice(eth);
        console.log("ETH price:", price);
        assertGt(price, 0, "ETH price not fetched");
    }
}
