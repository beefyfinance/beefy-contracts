#!/bin/bash

rm tmp/*.sol

echo "// SPDX-License-Identifier: MIT" > tmp/BeefyZapOneInchUniswapV2Compatible.sol
echo "// SPDX-License-Identifier: MIT" > tmp/StrategyCommonSolidlyStakerLP.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/TimelockV4.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Treasury.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/Multicall.sol
echo "// SPDX-License-Identifier: MIT" > tmp/DystopiaStaker.sol
# echo "// SPDX-License-Identifier: MIT" > tmp/TimelockController.sol
echo "// SPDX-License-Identifier: MIT" > tmp/BeefyVaultV6.sol


# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/Timelock.sol
# truffle-flattener node_modules/@openzeppelin-4/contracts/governance/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockV4.sol
truffle-flattener contracts/BIFI/vaults/BeefyVaultV6.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyVaultV6.sol
truffle-flattener contracts/BIFI/zaps/BeefyZapOneInchUniswapV2Compatible.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyZapOneInchUniswapV2Compatible.sol
# truffle-flattener contracts/BIFI/infra/BeefyFeeBatch.sol | sed '/SPDX-License-Identifier/d' >> tmp/Batch.sol
truffle-flattener contracts/BIFI/strategies/BeSolid/DystopiaStaker.sol | sed '/SPDX-License-Identifier/d' >> tmp/DystopiaStaker.sol
truffle-flattener contracts/BIFI/strategies/Common/StrategyCommonSolidlyStakerLP.sol | sed '/SPDX-License-Identifier/d' >> tmp/StrategyCommonSolidlyStakerLP.sol
# truffle-flattener node_modules/@openzeppelin/contracts/access/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockController.sol

