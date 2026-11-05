// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin-5/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-5/contracts/token/ERC20/IERC20.sol";
import {IAaveV4Spoke, IAaveV4Hub} from "../../../../contracts/BIFI/interfaces/aave/IAaveV4Spoke.sol";
import {BeefyVaultV7} from "../../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import {StrategyAaveV4Spoke} from "../../../../contracts/BIFI/strategies/Aave/StrategyAaveV4Spoke.sol";

contract MockToken is ERC20 {
    uint8 internal immutable precision;

    constructor(uint8 d) ERC20("Test token", "TEST") {
        precision = d;
    }

    function decimals() public view override returns (uint8) {
        return precision;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Models the Hub's floor-on-supply / ceil-on-withdraw share conversions.
/// Caps and Hub liquidity constraints are exercised against real contracts in the fork tests.
contract MockSpoke is IAaveV4Spoke, IAaveV4Hub {
    IERC20 public token;
    uint256 public index = 1e18;
    mapping(address => uint256) public shares;

    constructor(address t) {
        token = IERC20(t);
    }

    function getReserve(uint256 id) external view returns (Reserve memory) {
        require(id == 0, "reserve");
        return Reserve(address(token), IAaveV4Hub(address(this)), 0, 8, 0, 0, 0);
    }

    function setIndex(uint256 i) external {
        require(i >= index, "index decreased");
        index = i;
    }

    /// @dev Synthetic accounting stress only; not normal Aave interest-index behavior.
    function simulateLoss(uint256 i) external {
        require(i > 0 && i < index, "!loss");
        index = i;
    }

    function previewRemoveByShares(uint256, uint256 s) public view returns (uint256) {
        return s * index / 1e18;
    }

    function previewAddByAssets(uint256, uint256 a) public view returns (uint256) {
        return a * 1e18 / index;
    }

    function getUserSuppliedAssets(uint256, address u) public view returns (uint256) {
        return shares[u] * index / 1e18;
    }

    function getUserSuppliedShares(uint256, address u) external view returns (uint256) {
        return shares[u];
    }

    function supply(uint256, uint256 a, address u) external returns (uint256 s, uint256) {
        require(u == msg.sender, "self");
        require(a > 0, "!amount");
        s = a * 1e18 / index;
        require(s > 0, "!shares");
        token.transferFrom(msg.sender, address(this), a);
        shares[u] += s;
        return (s, a);
    }

    function withdraw(uint256, uint256 a, address u) external returns (uint256 s, uint256) {
        require(u == msg.sender, "self");
        uint256 bal = getUserSuppliedAssets(0, u);
        if (a > bal) a = bal;
        require(a > 0, "!amount");
        s = (a * 1e18 + index - 1) / index;
        shares[u] -= s;
        token.transfer(msg.sender, a);
        return (s, a);
    }
}

/// @dev Synthetic single-leaf Merkl distribution. No live proofs or campaign allocation are fabricated.
contract MockMerkl {
    bytes32 public root;
    mapping(bytes32 => bool) public claimed;

    function setRoot(address user, address token, uint256 amount) external {
        root = keccak256(abi.encode(user, token, amount));
    }

    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata
    ) external {
        for (uint256 i; i < users.length; ++i) {
            bytes32 leaf = keccak256(abi.encode(users[i], tokens[i], amounts[i]));
            require(leaf == root && !claimed[leaf], "proof");
            claimed[leaf] = true;
            IERC20(tokens[i]).transfer(users[i], amounts[i]);
        }
    }
}

/// @dev Funded deterministic swaps isolate strategy accounting from live DEX prices and routing.
contract MockSwapper {
    mapping(address => uint256) public units;

    function setToken(address token, uint256 unit) external {
        units[token] = unit;
    }

    function swap(address from, address to, uint256 amount) external returns (uint256 out) {
        require(units[from] > 0 && units[to] > 0, "route");
        out = amount * units[to] / units[from];
        IERC20(from).transferFrom(msg.sender, address(this), amount);
        IERC20(to).transfer(msg.sender, out);
    }
}

contract FlashLender {
    function lend(IERC20 token, uint256 amount, FlashAttacker borrower) external {
        uint256 beforeBal = token.balanceOf(address(this));
        token.transfer(address(borrower), amount);
        borrower.execute(amount);
        require(token.balanceOf(address(this)) >= beforeBal, "unpaid");
    }
}

contract FlashAttacker {
    IERC20 public want;
    BeefyVaultV7 public vault;
    StrategyAaveV4Spoke public strategy;
    address public reward;
    uint256 public rewardAmount;
    bool public directClaim;

    constructor(IERC20 w, BeefyVaultV7 v, StrategyAaveV4Spoke s, address r, uint256 a, bool direct) {
        want = w;
        vault = v;
        strategy = s;
        reward = r;
        rewardAmount = a;
        directClaim = direct;
    }

    function execute(uint256 amount) external {
        want.approve(address(vault), amount);
        vault.deposit(amount);
        address[] memory tokens = new address[](1);
        tokens[0] = reward;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = rewardAmount;
        bytes32[][] memory proofs = new bytes32[][](1);
        if (directClaim) {
            address[] memory users = new address[](1);
            users[0] = address(strategy);
            strategy.claimer().claim(users, tokens, amounts, proofs);
        } else {
            strategy.claim(tokens, amounts, proofs);
        }
        // Send the legitimate caller fee elsewhere, so assertions measure stolen vault rewards only.
        strategy.harvest(address(0xFEE));
        vault.withdrawAll();
        want.transfer(msg.sender, amount);
    }
}
