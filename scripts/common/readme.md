# Common Flow

One flow to deploy them alls (are that we dreams with of)

Getting Starting, run:

```
chmod +X ./run.sh
./run.sh
```

## About this

This all fork-proyect focus on create one flow to automate create for all commons LP pair form differents SWAPS and differents chain.

For 'common' we refers for: uniswaps LP pairs contract model and sushi masterchef model.

### Flow steps

1. Get Availables Pools for test ( Pools deployed - Pools on swaps)
2. Sort Availables Pools to choose the best one [APR, Liquirty/Volumen, totalAlloc != 0 (pool died)]
3. For each available pool, Deploy on local and test it with 'VaultLifeCycle.test.js' then with 'manual.test.js' (Read Mocha and write an output file)
4. For each pool that passed tests, Deploy it on mainnet
5. Update and PR Beefy-API with Deployed vaults jsons
6. Update and PR Beefy-APP with Deployed vaults jsons

### Steps to deploy vault

1. Choose a PLATFORM from swaps.js
2. Choose a POOL_ID
3. Test it on local
   2.1. Start local fork with `yarn run net:bsc`
   2.2. run local BTnD vault with `export POOL_ID=<pool-id-number> && export PLATFORM=<PLATFORM> && yarn run test:common:farm`
4. If all test passed and manual-test also passed, next step is deploy with `yarn run deploy:bsc:common:farm`
5. Check EVENT are generated on scan, event methos are:
   4.1. On Vault: [deposit, withdraw, depositAll, withdrawAll, transferOwnsership]
   4.2. On Strategy: [unpause, panic, harvest, transferOwnsership]
6. Update Beefy-API
   5.1. Check your deploy ouput on ./outputs/<CHAIN_NAME>-<lp_pair_name>-<isodate>.txt
   5.2. Copy-pasta 'beefy api object' on beefy-api/src/data/<platform>LpPools.json
   5.3. If lp has a new token, add it:
   5.3.1. run `ts-node scripts/add-token.ts --address "<TOKEN_ADDRESS>" --network "<CHAIN_NAME>"`
   5.3.2. add token object on beefy-api/packages/address-book/address-book/bsc/tokens/tokens.ts
   5.4. PR changes
7. Update Beefy-APP
   6.1. Check your deploy ouput on ./outputs/<CHAIN_NAME>-<lp_pair_name>-<isodate>.txt
   6.2. Copy-pasta 'beefy app object' on beefy-app/src/features/configure/vault/<CHAIN_NAME>\_pools.js
   6.3. Add new tokens image with run: `curl https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/<CHAIN_NAME>/assets/<token-address>/logo.png > <token-symbol>.png > beefy-app/src/images/single-assets/<token-symbol>.svg`
   6.4. test App on local `yarn install && yarn start`
   6.5. PR changes
