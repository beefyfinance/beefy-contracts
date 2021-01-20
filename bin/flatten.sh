#!/bin/bash

rm tmp/*.sol


echo "// SPDX-License-Identifier: MIT" > tmp/Strategy.sol
echo "// SPDX-License-Identifier: MIT" > tmp/Candidate.sol
echo "// SPDX-License-Identifier: MIT" > tmp/Vault.sol

truffle-flattener contracts/BIFI/vaults/BeefyVaultV2.sol | sed '/SPDX-License-Identifier/d' >> tmp/Vault.sol
truffle-flattener contracts/BIFI/strategies/Thugs/StrategyDoubleDrugs.sol | sed '/SPDX-License-Identifier/d' >> tmp/Strategy.sol
truffle-flattener contracts/BIFI/strategies/Thugs/StrategyHoesVaultV2.sol | sed '/SPDX-License-Identifier/d' >> tmp/Candidate.sol

