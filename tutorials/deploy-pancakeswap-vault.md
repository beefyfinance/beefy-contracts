# Deployment a PancakeSwap Vault on BSC

This tutorial will take you through the process of:

1. setting up the development environment
2. deploying a PancakeSwap vault to your development environment
3. deploying a PancakeSwap vault to BSC

These instructions are meant to aid new Strategy Dev's in deploying their first contract and seeks to complement the [readme.md][readme.md] file. This tutorial assumes the reader has a basic understanding of DeFi, Beefy Finance, Javascript, Solidity and Hardhat. We also assume the user has the following software installed:

- [node.js][node.js]
- [yarn][yarn]
- [solc][solc]

## Setting up a Development Environment

1. In your terminal, run the following command `yarn install` at the root of the project. This will install the project dependencies.
2. Create a `.env` file on the root of the project and add the private keys for each field. **NOTE THAT THE .env FILE SHOULD NEVER BE SHARED OR MADE PUBLIC.**

```bash
DEPLOYER_PK=ea6c4...
KEEPER_PK=ac0974b...
UPGRADER_PK=59c699...
```

## Deploying a Vault to your Development Environment

1. Navigate to and open the `deploy-pancakeswap-vault.js` script.
2. Change the tokens listed in the destructured object to match the tokens needed for deployment. If necessary, you can add tokens not listed in the `addressBook` manually.

   ```js
   const {
      platforms: { pancake, beefyfinance },
      tokens: {
         CAKE: { address: CAKE },
         WBNB: { address: WBNB },
         BUSD: { address: BUSD },
      },
   } = addressBook.bsc;
   
   const newToken = web3.utils.toChecksumAddress("0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82");
   ```

3. Find the LP address (`lpAddresses.56`) and pool id (`pid`) of the LP token corresponding to the vault that will be deployed. These values can be found in PancakeSwap's [repository][repository].
4. Replace the address assigned to the `want` variable with the lp address.
5. Update the `vaultParams` with the correct name and symbol.
6. Replace the variables under the `strategyParams` object as follows:

   - `poolId` is the same Id found in step 2.
   - `strategist` is an address owned by the deployer, its recommended to use a separate address on a hardware wallet.
   - `outputToNativeRoute` is an array where the first element is the reward token (e.g. CAKE, JOE, etc.) and the second element is the native token (e.g. WBNB, WAVAX, etc.)
   - `outputToLp0Route` is the path from the reward token to the first token in the LP.
   - `outputToLp1Route` is the path from the reward token to the second token in the LP.

7. Update the `contractNames` with the appropriate vault and strategy names.
8. In this tutorial we will be forking BSC, this creates a local version of BSC that we can deploy, and interact with. To fork the BSC chain you will need to use an archival node (Ankr public RPCs provide these).

9. Run `npx hardhat node --fork bsc` to create a fork. A message similar to the following shall appear in the terminal.

   ```bash
   Forking bsc from RPC: https://rpc.ankr.com/bsc
   Started HTTP and WebSocket JSON-RPC server at http://127.0.0.1:8545/

   Accounts
   ========
   Account #0: 0x2546bcd3c84621e976d8185a91a922ae77ecec30 (1000000 ETH)
   Private Key: 0xea6c44ac03bff858b476bba40716402b03e41b8e97e276d1baec7c37d42484a0

   Account #1: 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266 (1000000 ETH)
   Private Key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

   Account #2: 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 (1000000 ETH)
   Private Key: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
   ```

10. Open a separate terminal and run `npx hardhat run tutorials/deploy-pancakeswap-vault.js --network localhost` to execute the script on the BSC node. Once the script completes execution you should see a similar message in your second terminal.

    ```bash
    Deploying: Moo CakeV2 CAKE-BNB
    
    Vault: 0x42AD3aE0B79Fa253ab732eba8FCF38864Ad4abf0
    Strategy: 0x6F5F90122d77091a97cDD5DAF78217DCEafE0D40
    Want: 0x0eD7e52944161450477ee417DE9Cd3a859b14fD0
    PoolId: 2

    Running post deployment
    Setting pendingRewardsFunctionName to 'pendingCake'
    Transfered Vault Ownership to 0xA2E6391486670D2f1519461bcc915E4818aD1c9a
    ```

11. From here I recommend writing/running your own set of tests to ensure everything was deployed properly. We recommend reviewing the `test/prod/VaultLifecycle.test.js` test script to get started. When ready you can run your tests using the following command `npx hardhat test --network localhost <PATH_TO_YOUR_TEST>`.

## Deploying a Vault to BSC

1. In the `.env` file change the `DEPLOYER_PK` to the private keys of the address used to deploy the contract on BSC. Delete the remaining variables in the `.env` file as they will not be needed in this section.

   **NOTE THESE KEYS SHOULD NEVER BE SHARED WITH ANYONE. DOING SO WILL COMPROMISE THE ADDRESS AND ALL ASSETS HELD BY THE ADDRESS.**

2. You will deploy the contract to the BSC chain using the same script from 'Deploying a Vault to your Development Environment'. In the `deploy-pancakeswap-vault.js` script, change the `strategyParams.strategist` public keys to the address matching the private keys listed in your `.env` file.
3. Since you will be connecting directly to BSC you may change the RPC URL found in the `hardhat.config.ts` file.
4. At this point you should be ready to deploy your vault to the BSC network. You can do this by simply running the following command `npx hardhat run tutorials/deploy-pancakeswap-vault.js --network bsc`.
5. Once the script completes execution you should be able to verify that it deployed successfully using the links in the terminal or querying bscsan using the Vault or Strategy addresses. From here we recommend performing manual tests as suggested in the [readme.md][readme.md]. NOTE, YOU MUST PERMISSION THE VAULT TO TRANSFER YOUR FUNDS BY SUBMITTING AN `approve()` TRANSACTION TO THE LP TOKEN WITH THE VAULT ADDRESS AND THE AMOUNT.

[readme.md]: beefy-contracts/readme.md
[node.js]: https://nodejs.org
[yarn]: https://yarnpkg.com
[solc]: https://docs.soliditylang.org
[repository]: https://github.com/pancakeswap/pancake-frontend/blob/master/src/config/constants/farms.ts