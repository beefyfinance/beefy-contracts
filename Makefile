include .env

.EXPORT_ALL_VARIABLES:
FOUNDRY_ETH_RPC_URL?=https://${NETWORK}.infura.io/v3/${INFURA_KEY}
FOUNDRY_FORK_BLOCK_NUMBER?=34993343
ETHERSCAN_API_KEY?=${ETHERSCAN_KEY}

default:; @forge build
test:; @forge test --match-contract StrategyLLCurveLPTest
test-gas-report:; @forge test --gas-report

.PHONY: build test snapshot quote