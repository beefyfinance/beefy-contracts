#!/bin/bash

rm tmp/*.sol


echo "// SPDX-License-Identifier: MIT" > tmp/Vault.sol
echo "// SPDX-License-Identifier: MIT" > tmp/Strategy.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Candidate.sol

truffle-flattener contracts/BIFI/vaults/BeefyVaultV3.sol | sed '/SPDX-License-Identifier/d' >> tmp/Vault.sol
truffle-flattener contracts/BIFI/strategies/Cake/StrategyCakeMirrorLP.sol | sed '/SPDX-License-Identifier/d' >> tmp/Strategy.sol
# truffle-flattener contracts/BIFI/strategies/Thugs/StrategyHoesVaultV2.sol | sed '/SPDX-License-Identifier/d' >> tmp/Candidate.sol

