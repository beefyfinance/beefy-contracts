#!/bin/bash

rm tmp/*.sol

echo "// SPDX-License-Identifier: MIT" > tmp/BeefyVaultV6Native.sol
echo "// SPDX-License-Identifier: MIT" > tmp/StrategyStella.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/TimelockV4.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Treasury.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Multicall.sol
echo "// SPDX-License-Identifier: MIT" > tmp/StrategyAaveSupplyOnlyOptimismBeets.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/TimelockController.sol
echo "// SPDX-License-Identifier: MIT" > tmp/BeefyFeeBatchV3.sol


# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/Timelock.sol
# truffle-flattener node_modules/@openzeppelin-4/contracts/governance/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockV4.sol
truffle-flattener contracts/BIFI/vaults/BeefyVaultV6Native.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyVaultV6Native.sol
truffle-flattener contracts/BIFI/infra/BeefyFeeConfigurator.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyFeeConfigurator.sol
# truffle-flattener contracts/BIFI/infra/BeefyFeeBatch.sol | sed '/SPDX-License-Identifier/d' >> tmp/Batch.sol
truffle-flattener contracts/BIFI/strategies/Common/StrategyCommonChefLP.sol | sed '/SPDX-License-Identifier/d' >> tmp/StrategyCommonChefLP.sol
truffle-flattener contracts/BIFI/strategies/Aave/StrategyAaveSupplyOnlyOptimismBeets.sol | sed '/SPDX-License-Identifier/d' >> tmp/StrategyAaveSupplyOnlyOptimismBeets.sol
# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockController.sol

