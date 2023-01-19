#!/bin/bash

rm tmp/*.sol

echo "// SPDX-License-Identifier: MIT" > tmp/BeefyZapOneInch.sol
echo "// SPDX-License-Identifier: MIT" > tmp/StrategyCommonChefLPProxySweeper.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/TimelockV4.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Treasury.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Multicall.sol
echo "// SPDX-License-Identifier: MIT" > tmp/BeefyFeeBatch.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/TimelockController.sol
echo "// SPDX-License-Identifier: MIT" > tmp/BeefyVaultV7.sol
echo "// SPDX-License-Identifier: MIT" > tmp/BeefyVaultV7Factory.sol
echo "// SPDX-License-Identifier: MIT" > tmp/BeefyRewardPool.sol


# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/Timelock.sol
# truffle-flattener node_modules/@openzeppelin-4/contracts/governance/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockV4.sol
truffle-flattener contracts/BIFI/vaults/BeefyVaultV7.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyVaultV7.sol
truffle-flattener contracts/BIFI/vaults/BeefyVaultV7Factory.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyVaultV7Factory.sol
truffle-flattener contracts/BIFI/zaps/BeefyZapOneInch.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyZapOneInch.sol
truffle-flattener contracts/BIFI/infra/BeefyFeeBatchV3UniV3.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyFeeBatch.sol
truffle-flattener contracts/BIFI/infra/BeefyRewardPool.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyRewardPool.sol
truffle-flattener contracts/BIFI/zaps/BeefyPairFeeDataSource.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyPairFeeDataSource.sol
truffle-flattener contracts/BIFI/strategies/Common/StrategyCommonChefLPProxySweeper.sol | sed '/SPDX-License-Identifier/d' >> tmp/StrategyCommonChefLPProxySweeper.sol
# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockController.sol

