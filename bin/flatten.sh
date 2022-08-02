#!/bin/bash

rm tmp/*.sol

echo "// SPDX-License-Identifier: MIT" > tmp/BeefyVaultV6.sol
echo "// SPDX-License-Identifier: MIT" > tmp/StrategyStella.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/TimelockV4.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Treasury.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Multicall.sol
echo "// SPDX-License-Identifier: MIT" > tmp/VeloStaker.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/TimelockController.sol
echo "// SPDX-License-Identifier: MIT" > tmp/BeefyFeeBatchV3.sol


# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/Timelock.sol
# truffle-flattener node_modules/@openzeppelin-4/contracts/governance/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockV4.sol
truffle-flattener contracts/BIFI/vaults/BeefyVaultV6.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyVaultV6.sol
truffle-flattener contracts/BIFI/infra/BeefyFeeBatchV3.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyFeeBatchV3.sol
# truffle-flattener contracts/BIFI/infra/BeefyFeeBatch.sol | sed '/SPDX-License-Identifier/d' >> tmp/Batch.sol
truffle-flattener contracts/BIFI/strategies/Curve/StrategyCurveLP.sol | sed '/SPDX-License-Identifier/d' >> tmp/StrategyCurveLP.sol
truffle-flattener contracts/BIFI/strategies/Velodrome/VeloStaker.sol | sed '/SPDX-License-Identifier/d' >> tmp/VeloStaker.sol
# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockController.sol

