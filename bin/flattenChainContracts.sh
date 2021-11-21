#!/bin/bash

rm tmp/*.sol

echo "// SPDX-License-Identifier: MIT" > tmp/TimelockController.sol
truffle-flattener node_modules/@openzeppelin-4/contracts/governance/TimelockController.sol | sed '/SPDX-License-Identifier/d' >> tmp/TimelockController.sol

echo "// SPDX-License-Identifier: MIT" > tmp/BeefyTreasury.sol
hardhat flatten contracts/BIFI/infra/BeefyTreasury.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyTreasury.sol

echo "// SPDX-License-Identifier: MIT" > tmp/Multicall.sol
hardhat flatten contracts/BIFI/utils/Multicall.sol | sed '/SPDX-License-Identifier/d' >> tmp/Multicall.sol

echo "// SPDX-License-Identifier: MIT" > tmp/BeefyRewardPool.sol
hardhat flatten contracts/BIFI/infra/BeefyRewardPool.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyRewardPool.sol

echo "// SPDX-License-Identifier: MIT" > tmp/BeefyFeeBatchV2.sol
hardhat flatten contracts/BIFI/infra/BeefyFeeBatchV2.sol | sed '/SPDX-License-Identifier/d' >> tmp/BeefyFeeBatchV2.sol


