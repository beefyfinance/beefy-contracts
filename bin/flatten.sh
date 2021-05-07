#!/bin/bash

rm tmp/*.sol

# echo "// SPDX-License-Identifier: MIT" > tmp/Vault.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Vault.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Batch.sol
# # echo "// SPDX-License-Identifier: MIT" > tmp/Treasury.sol
# # echo "// SPDX-License-Identifier: MIT" > tmp/Candidate.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Balancer.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Pool.sol


# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/Vault.sol
# truffle-flattener contracts/BIFI/strategies/Common/StrategyRewardPoolBsc.sol | sed '/SPDX-License-Identifier/d' >> tmp/Strategy.sol
# truffle-flattener contracts/BIFI/infra/BeefyFeeBatch.sol | sed '/SPDX-License-Identifier/d' >> tmp/Batch.sol
# # truffle-flattener contracts/BIFI/strategies/Cake/StrategyCakeCommunityLP.sol | sed '/SPDX-License-Identifier/d' >> tmp/Candidate.sol
# # truffle-flattener contracts/BIFI/experiments/BeefyTreasury.sol | sed '/SPDX-License-Identifier/d' >> tmp/Treasury.sol
# truffle-flattener contracts/BIFI/strategies/Common/YieldBalancer.sol | sed '/SPDX-License-Identifier/d' >> tmp/Balancer.sol
yarn truffle-flattener contracts/BIFI/strategies/Sushi/StrategyPolygonSushiLP.sol | sed '/SPDX-License-Identifier/d' >> tmp/Pool.sol

