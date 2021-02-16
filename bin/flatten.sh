#!/bin/bash

rm tmp/*.sol


echo "// SPDX-License-Identifier: MIT" > tmp/Strategy.sol
echo "// SPDX-License-Identifier: MIT" > tmp/Vault.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Treasury.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Candidate.sol
echo "// SPDX-License-Identifier: MIT" > tmp/Balancer.sol

truffle-flattener contracts/BIFI/vaults/BeefyVaultV3.sol | sed '/SPDX-License-Identifier/d' >> tmp/Vault.sol
truffle-flattener contracts/BIFI/strategies/Cake/StrategyCake.sol | sed '/SPDX-License-Identifier/d' >> tmp/Strategy.sol
# truffle-flattener contracts/BIFI/strategies/Cake/StrategyCakeCommunityLP.sol | sed '/SPDX-License-Identifier/d' >> tmp/Candidate.sol
# truffle-flattener contracts/BIFI/experiments/BeefyTreasury.sol | sed '/SPDX-License-Identifier/d' >> tmp/Treasury.sol
truffle-flattener contracts/BIFI/strategies/Common/YieldBalancer.sol | sed '/SPDX-License-Identifier/d' >> tmp/Balancer.sol

