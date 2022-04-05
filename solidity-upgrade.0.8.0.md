# solidity 0.8.0

Vault: 0x44Dfa74Ee2B56c1004980B3CD1fBc69bfC04A206
Strategy: 0xdafF49F1bdBe7b1e3Bea83E2B4E0e40CE11E2e86
Want: 0x26A2abD79583155EA5d34443b62399879D42748A
PoolId: 0

Running post deployment
Setting call fee to '11'
Transfering Vault Owner to 0xc8F3D9994bb1670F5f3d78eBaBC35FA8FdEEf8a2

# tests with fuzzing, no console log

Running 6 tests for forge/test/ProdVaultTest.t.sol:ProdVaultTest
[PASS] test_correctOwnerAndKeeper(uint8) (runs: 256, μ: 16711, ~: 16711)
[PASS] test_depositAndWithdraw(uint8) (runs: 256, μ: 515774, ~: 515774)
[PASS] test_harvest(uint8) (runs: 256, μ: 866346, ~: 866348)
[PASS] test_harvestOnDeposit(uint8) (runs: 256, μ: 14239, ~: 14239)
[PASS] test_multipleUsers(uint8) (runs: 256, μ: 1016293, ~: 1016293)
[PASS] test_panic(uint8) (runs: 256, μ: 592803, ~: 592804)
Test result: ok. 6 passed; 0 failed; finished in 5.14s

# tests with fuzzing, console log

Running 6 tests for forge/test/ProdVaultTest.t.sol:ProdVaultTest
[PASS] test_correctOwnerAndKeeper(uint8) (runs: 256, μ: 19562, ~: 19562)
[PASS] test_depositAndWithdraw(uint8) (runs: 256, μ: 516053, ~: 516052)
[PASS] test_harvest(uint8) (runs: 256, μ: 866624, ~: 866624)
[PASS] test_harvestOnDeposit(uint8) (runs: 256, μ: 14587, ~: 14587)
[PASS] test_multipleUsers(uint8) (runs: 256, μ: 1016641, ~: 1016641)
[PASS] test_panic(uint8) (runs: 256, μ: 593082, ~: 593081)
Test result: ok. 6 passed; 0 failed; finished in 5.40s

# tests without fuzzing

```
Running 6 tests for forge/test/ProdVaultTest.t.sol:ProdVaultTest
[PASS] test_correctOwnerAndKeeper() (gas: 16597)
[PASS] test_depositAndWithdraw() (gas: 515677)
Logs:
  Approving want spend.
  Depositing all want into vault, 50000000000000000000
  Shifting forward seconds, 100
  Withdrawing all want from vault
  Final user want balance, 49950000000000000000

[PASS] test_harvest() (gas: 866317)
Logs:
  Approving want spend.
  Depositing all want into vault, 50000000000000000000
  Shifting forward seconds, 1000
  Harvesting vault.
  Withdrawing all want.

[PASS] test_harvestOnDeposit() (gas: 14104)
Logs:
  Vault is NOT harvestOnDeposit.

[PASS] test_multipleUsers() (gas: 1016159)
Logs:
  Approving want spend.
  Depositing all want into vault, 50000000000000000000
  Getting want for user2.
  Shifting forward seconds, 1000
  User2 depositAll.
  Approving want spend.
  Depositing all want into vault, 50000000000000000000
  Shifting forward seconds, 1000
  User1 withdrawAll.

[PASS] test_panic() (gas: 592721)
Logs:
  Approving want spend.
  Depositing all want into vault, 50000000000000000000
  Calling panic()
  Getting user more want.
  Approving more want.
  Trying to deposit while panicked.
  User withdraws all.

Test result: ok. 6 passed; 0 failed; finished in 1.13s
╭────────────────────┬─────────────────┬────────┬────────┬────────┬─────────╮
│ VaultUser contract ┆                 ┆        ┆        ┆        ┆         │
╞════════════════════╪═════════════════╪════════╪════════╪════════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆        ┆        ┆        ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 310549             ┆ 1583            ┆        ┆        ┆        ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg    ┆ median ┆ max    ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ approve            ┆ 23231           ┆ 26647  ┆ 27831  ┆ 27831  ┆ 6       │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ depositAll         ┆ 51365           ┆ 271042 ┆ 355131 ┆ 355131 ┆ 6       │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ withdrawAll        ┆ 47724           ┆ 94201  ┆ 98700  ┆ 131680 ┆ 4       │
╰────────────────────┴─────────────────┴────────┴────────┴────────┴─────────╯
```
