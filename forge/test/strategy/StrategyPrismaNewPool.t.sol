// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

//import "forge-std/Test.sol";
import "../../../node_modules/forge-std/src/Test.sol";

// Users
import "../users/VaultUser.sol";
// Interfaces
import "../interfaces/IERC20Like.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/interfaces/common/IERC20Extended.sol";
import "../../../contracts/BIFI/strategies/Curve/StrategyPrisma.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyPrismaNewPoolTest is Test {

    IStrategy constant PROD_STRAT = IStrategy(0x2486c5fa59Ba480F604D5A99A6DAF3ef8A5b4D76);

    IVault vault;
    StrategyPrisma strategy;
    VaultUser user;
    uint256 wantAmount = 50000 ether;
    address newRewardPool;

    function setUp() public {
        user = new VaultUser();
        address vaultAddress = vm.envAddress("VAULT");
        newRewardPool = vm.envAddress("NEW_POOL");

        vault = IVault(vaultAddress);
        strategy = StrategyPrisma(vault.strategy());
        console.log("Testing vault at", vaultAddress);
        console.log(vault.name(), vault.symbol());

        bytes memory callData = abi.encodeCall(StrategyPrisma.setPrismaRewardPool, (newRewardPool));
        console.log("owner:", strategy.owner());
        console.log("target:", address(strategy));
        console.log("data:", bytesToStr(callData));
    }

    function test_setPrismaRewardPool() external {
        address oldRewardPool = strategy.rewardPool();
        uint rewardPoolBal = IPrismaRewardPool(oldRewardPool).balanceOf(address(strategy));
        assertEq(vault.balance(), rewardPoolBal, "RewardPool balance != vault balance");

        vm.prank(strategy.owner());
        strategy.setPrismaRewardPool(newRewardPool);
        rewardPoolBal = IPrismaRewardPool(oldRewardPool).balanceOf(address(strategy));
        assertEq(rewardPoolBal, 0, "Old rewardPool balance != 0");
        uint gaugeBal = IPrismaRewardPool(newRewardPool).balanceOf(address(strategy));
        assertEq(vault.balance(), gaugeBal, "New rewardPool balance != vault balance");

        vm.prank(strategy.keeper());
        strategy.panic();
        assertEq(strategy.balanceOfWant(), gaugeBal, "Strategy balance != vault balance after panic");
        assertEq(strategy.balanceOfPool(), 0, "New rewardPool balance != 0 after panic");

        vm.prank(strategy.keeper());
        strategy.unpause();
        assertEq(vault.balance(), gaugeBal, "Vault balance is wrong after panic/unpause");
    }

    function bytesToStr(bytes memory buffer) public pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);
        bytes memory _base = "0123456789abcdef";
        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }
        return string(abi.encodePacked("0x", converted));
    }
}