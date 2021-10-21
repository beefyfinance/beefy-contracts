#!/bin/bash

rm tmp/*.sol

# echo "// SPDX-License-Identifier: MIT" > tmp/Vault.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/FeeBatcher.sol
echo "// SPDX-License-Identifier: MIT" > tmp/TimelockV4.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Treasury.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Candidate.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Balancer.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/TimelockController.sol


# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/Timelock.sol
truffle-flattener node_modules/@openzeppelin-4/contracts/governance/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockV4.sol
# truffle-flattener contracts/BIFI/infra/BeefyLaunchpool.sol | sed '/SPDX-License-Identifier/d' >> tmp/Pool.sol
# truffle-flattener contracts/BIFI/infra/BeefyFeeBatch.sol | sed '/SPDX-License-Identifier/d' >> tmp/Batch.sol
<<<<<<< HEAD
truffle-flattener contracts/BIFI/infra/BeefyFeeBatchV2.sol | sed '/SPDX-License-Identifier/d' >> tmp/FeeBatcher.sol
=======
# truffle-flattener contracts/BIFI/infra/BeefyFeeBatchSimpleV2.sol | sed '/SPDX-License-Identifier/d' >> tmp/FeeBatcher.sol
>>>>>>> master
# # truffle-flattener contracts/BIFI/experiments/BeefyTreasury.sol | sed '/SPDX-License-Identifier/d' >> tmp/Treasury.sol
# truffle-flattener contracts/BIFI/strategies/Common/YieldBalancer.sol | sed '/SPDX-License-Identifier/d' >> tmp/Balancer.sol
# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockController.sol

