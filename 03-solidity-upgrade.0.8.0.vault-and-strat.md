# solidity 0.8.0

Vault: 0x35aACc4c63ac4e3459d67964014E158d5132a25e
Strategy: 0x696709e199708b4263e103faa4F969ac319aF746
Want: 0x26A2abD79583155EA5d34443b62399879D42748A
PoolId: 0

Running post deployment
Setting call fee to '11'
Transfering Vault Owner to 0xc8F3D9994bb1670F5f3d78eBaBC35FA8FdEEf8a2

# tests with fuzzing

Running 6 tests for forge/test/ProdVaultTest.t.sol:ProdVaultTest
[PASS] test_correctOwnerAndKeeper(uint8) (runs: 256, μ: 16711, ~: 16711)
[PASS] test_depositAndWithdraw(uint8) (runs: 256, μ: 515774, ~: 515774)
[PASS] test_harvest(uint8) (runs: 256, μ: 866346, ~: 866348)
[PASS] test_harvestOnDeposit(uint8) (runs: 256, μ: 14239, ~: 14239)
[PASS] test_multipleUsers(uint8) (runs: 256, μ: 1016293, ~: 1016293)
[PASS] test_panic(uint8) (runs: 256, μ: 592803, ~: 592804)
Test result: ok. 6 passed; 0 failed; finished in 5.14s

# tests without fuzzing

```
Running 6 tests for forge/test/ProdVaultTest.t.sol:ProdVaultTest
[PASS] test_correctOwnerAndKeeper() (gas: 16508)
[PASS] test_depositAndWithdraw() (gas: 513641)
Logs:
  Approving want spend.
  Depositing all want into vault, 50000000000000000000
  Shifting forward seconds, 100
  Withdrawing all want from vault
  Final user want balance, 49950000000000000000

[PASS] test_harvest() (gas: 860648)
Logs:
  Approving want spend.
  Depositing all want into vault, 50000000000000000000
  Shifting forward seconds, 1000
  Harvesting vault.
  Withdrawing all want.

[PASS] test_harvestOnDeposit() (gas: 14041)
Logs:
  Vault is NOT harvestOnDeposit.

[PASS] test_multipleUsers() (gas: 1011178)
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

[FAIL. Reason: Revert] test_panic() (gas: 493844)
Logs:
  Approving want spend.
  Depositing all want into vault, 50000000000000000000
  Calling panic()

Test result: FAILED. 5 passed; 1 failed; finished in 1.38s
╭────────────────────┬─────────────────┬────────┬────────┬────────┬─────────╮
│ VaultUser contract ┆                 ┆        ┆        ┆        ┆         │
╞════════════════════╪═════════════════╪════════╪════════╪════════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆        ┆        ┆        ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 310549             ┆ 1583            ┆        ┆        ┆        ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg    ┆ median ┆ max    ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ approve            ┆ 25331           ┆ 27331  ┆ 27831  ┆ 27831  ┆ 5       │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ depositAll         ┆ 153374          ┆ 313778 ┆ 353879 ┆ 353879 ┆ 5       │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ withdrawAll        ┆ 85444           ┆ 108697 ┆ 109964 ┆ 130684 ┆ 3       │
╰────────────────────┴─────────────────┴────────┴────────┴────────┴─────────╯

```
