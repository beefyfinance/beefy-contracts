# solidity 0.6.0

Vault: 0x263A2E7BCcd8DE4D9253e263550Eda3007684BD1
Strategy: 0x6E4016F744C2A44f3D74a2764Eda7F13480542D3
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
[PASS] test_panic(uint8) (runs: 256, μ: 592802, ~: 592802)
Test result: ok. 6 passed; 0 failed; finished in 5.20s

# tests without fuzzing

```
Running 6 tests for forge/test/ProdVaultTest.t.sol:ProdVaultTest
[PASS] test_correctOwnerAndKeeper(uint8) (runs: 256, μ: 16733, ~: 16733)
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

[PASS] test_multipleUsers() (gas: 1016181)
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

Test result: ok. 6 passed; 0 failed; finished in 832.38ms
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
