#!/bin/bash

rm tmp/*.sol

echo "// SPDX-License-Identifier: MIT" > tmp/BeefyZapOneInch.sol
echo "// SPDX-License-Identifier: MIT" > tmp/StrategyBeetsMultiRewardGauge.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/TimelockV4.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Treasury.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Multicall.sol
echo "// SPDX-License-Identifier: MIT" > tmp/BeefyPairFeeDataSource.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/TimelockController.sol
echo "// SPDX-License-Identifier: MIT" > tmp/BeefyVaultV6.sol


# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/Timelock.sol
# truffle-flattener node_modules/@openzeppelin-4/contracts/governance/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockV4.sol
truffle-flattener contracts/BIFI/vaults/BeefyVaultV6.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyVaultV6.sol
truffle-flattener contracts/BIFI/zaps/BeefyZapOneInch.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyZapOneInch.sol
# truffle-flattener contracts/BIFI/infra/BeefyFeeBatch.sol | sed '/SPDX-License-Identifier/d' >> tmp/Batch.sol
truffle-flattener contracts/BIFI/zaps/BeefyPairFeeDataSource.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyPairFeeDataSource.sol
truffle-flattener contracts/BIFI/strategies/Beethovenx/StrategyBeetsMultiRewardGauge.sol | sed '/SPDX-License-Identifier/d' >> tmp/StrategyBeetsMultiRewardGauge.sol
# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockController.sol

