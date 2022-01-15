#!/bin/bash

rm tmp/*.sol

echo "// SPDX-License-Identifier: MIT" > tmp/BeefyVaultV6.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/FeeBatcher.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/TimelockV4.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Treasury.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Candidate.sol
echo "// SPDX-License-Identifier: MIT" > tmp/StrategyMdexChefLP.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/TimelockController.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/RewardPool.sol


# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/Timelock.sol
# truffle-flattener node_modules/@openzeppelin-4/contracts/governance/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockV4.sol
truffle-flattener contracts/BIFI/vaults/BeefyVaultV6.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyVaultV6.sol
# truffle-flattener contracts/BIFI/infra/BeefyRewardPool.sol | sed '/SPDX-License-Identifier/d' >> tmp/RewardPool.sol
# truffle-flattener contracts/BIFI/infra/BeefyFeeBatch.sol | sed '/SPDX-License-Identifier/d' >> tmp/Batch.sol
# truffle-flattener contracts/BIFI/infra/BeefyFeeBatchV2.sol | sed '/SPDX-License-Identifier/d' >> tmp/FeeBatcher.sol
truffle-flattener contracts/BIFI/strategies/Mdex/StrategyMdexChefLP.sol | sed '/SPDX-License-Identifier/d' >> tmp/StrategyMdexChefLP.sol
# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockController.sol

