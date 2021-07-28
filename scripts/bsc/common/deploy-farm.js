const fs = require('fs');
const hardhat = require("hardhat");
const { addressBook } = require("blockchain-addressbook")
const { getLpPair, writer, resolveSwapRoute } = require("../../../utils/farms.helpers");
const registerSubsidy = require("../../../utils/registerSubsidy");
const predictAddresses = require("../../../utils/predictAddresses");

/**
 * Main Variables
 * this all are 'variables' to modify in case use another platform or blockchain
 */
const POOL_ID = process.env.POOL_ID
const CHAIN_NAME = process.env.CHAIN_NAME || 'bsc'

const PLATFORM = {
  name: process.env.PLATFORM_NAME || 'PancakeSwap',
  prefix: process.env.PLATFORM_PREFIX || 'CakeV2',
  url: process.env.PLATFORM_URL || 'exchange.pancakeswap.finance/#/',
  chef: process.env.PLATFORM_CHEF || addressBook.bsc.platforms.pancake.masterchef,
  router: process.env.PLATFORM_ROUTER || addressBook.bsc.platforms.pancake.router,
  tokens: {
    reward: process.env.PLATFORM_TOKEN_REWARD || addressBook.bsc.tokens.CAKE,
    wnative: process.env.PLATFORM_TOKEN_WNATIVE || addressBook.bsc.tokens.WBNB
  }
}

const CONTRACTS = {
  vault: {
    name: "BeefyVaultV6",
    address: '',
    params: ''
  },
  strategy: {
    name: "StrategyCommonChefLP",
    address: '',
    params: ''
  }
}

const { BUSD, USDT, USDC } = addressBook[CHAIN_NAME].tokens;
const proxieTokenAddress = [PLATFORM.tokens.reward, PLATFORM.tokens.wnative, BUSD, USDT, USDC].map(t => t.address);


const main = async () => {
  console.log('Platform:', PLATFORM, '\n')
  const deployer = await ethers.getSigner();
  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc: hardhat.network.config.url });
  const lpPair = await getLpPair({ poolId: POOL_ID, deployer, chefAddress: PLATFORM.chef })
  const write = writer({ dirname: `${__dirname}/outputs`, filename: `${hardhat.network.name}-${lpPair.name}` })
  const swapRouteConfig = {
    toLp0Route: {
      input: PLATFORM.tokens.reward.address,
      proxies: proxieTokenAddress, 
      preferredProxy: lpPair.token1.address, 
      output: lpPair.token0.address, 
      wnative: PLATFORM.tokens.wnative
    },
    toLp1Route: {
      input: PLATFORM.tokens.reward.address,
      proxies: proxieTokenAddress, 
      preferredProxy: lpPair.token0.address, 
      output: lpPair.token1.address, 
      wnative: PLATFORM.tokens.wnative
    },
  }

  const KEEPER = process.env.KEEPER || deployer.address

  CONTRACTS.vault.address = predictedAddresses.vault
  CONTRACTS.strategy.address = predictedAddresses.strategy

  CONTRACTS.vault.params = {
    strategy: predictedAddresses.strategy,
    mooName: `Moo ${PLATFORM.prefix} ${lpPair.name}`,
    mooSymbol: `moo${PLATFORM.prefix}${lpPair.name}`,
    delay: 21600,
  }

  CONTRACTS.strategy.params = {
    want: lpPair.address,
    poolId: POOL_ID,
    chef: PLATFORM.chef,
    vault: predictedAddresses.vault,
    router: PLATFORM.router, // Pancakeswap Router V2
    keeper: KEEPER,
    strategist: deployer.address, // your address for rewards
    beefyFeeRecipient: addressBook[CHAIN_NAME].platforms.beefyfinance.beefyFeeRecipient,
    toNativeRoute: [PLATFORM.tokens.reward.address, PLATFORM.tokens.wnative.address],
    toLp0Route: resolveSwapRoute(swapRouteConfig.toLp0Route),
    toLp1Route: resolveSwapRoute(swapRouteConfig.toLp1Route),
  };

  console.log('Vault:', CONTRACTS.vault, '\n')
  write(`Vault:\n${JSON.stringify(CONTRACTS.vault)}\n`)
  console.log('Strategy', CONTRACTS.strategy, '\n');
  write(`Strategy:\n${JSON.stringify(CONTRACTS.strategy)}\n`)

  if (Object.values(CONTRACTS.vault.params).some((v) => v === undefined) || Object.values(CONTRACTS.strategy.params).some((v) => v === undefined) || CONTRACTS.vault.name === undefined || CONTRACTS.strategy.name === undefined) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory(CONTRACTS.vault.name);
  const Strategy = await ethers.getContractFactory(CONTRACTS.strategy.name);

  console.log("\n= Deploying =>\t", CONTRACTS.vault.params.mooName);

  const vault = await Vault.deploy(...Object.values(CONTRACTS.vault.params));
  await vault.deployed();

  const strategy = await Strategy.deploy(...Object.values(CONTRACTS.strategy.params));
  await strategy.deployed();

  console.log("Vault deployed on ", vault.address)
  console.log("Strategy deployed on ", strategy.address);

  const outputs = {
    api: {
      id: `${PLATFORM.prefix.toLocaleLowerCase()}-${lpPair.name.toLowerCase()}`,
      name: `${lpPair.name} LP`,
      token: `${lpPair.name} LP2`,
      tokenDescription: `${PLATFORM.name}`,
      tokenAddress: CONTRACTS.strategy.params.want,
      tokenDecimals: Number(`${lpPair.decimals.replace('1e','')}`),
      tokenDescriptionUrl: '#',
      earnedToken: CONTRACTS.vault.params.mooSymbol,
      earnedTokenAddress: vault.address,
      earnContractAddress: vault.address,
      pricePerFullShare: 1,
      tvl: 0,
      oracle: 'lps',
      oracleId: `${PLATFORM.prefix}-${lpPair.name.toLowerCase()}`,
      oraclePrice: 0,
      depositsPaused: false,
      status: 'active',
      platform: PLATFORM.name,
      assets: [lpPair.token0.symbol, lpPair.token1.symbol],
      callFee: 0.5,
      addLiquidityUrl: `https://${PLATFORM.url}/add/${lpPair.token0.address}/${lpPair.token1.address}`,
      buyTokenUrl: `https://${PLATFORM.url}/swap?inputCurrency=${lpPair.token0.address}&outputCurrency=${lpPair.token1.address}`,
    },
    app: {
      name: `${PLATFORM.prefix.toLocaleLowerCase()}-${lpPair.name.toLowerCase()}`,
      address: `${lpPair.address}`,
      decimals: `${lpPair.decimals}`,
      poolId: Number(POOL_ID),
      chainId: 56,
      lp0: {
        address: `${lpPair.token0.address}`,
        oracle: "tokens",
        oracleId: `${lpPair.token0.symbol}`,
        decimals: `${lpPair.token1.decimals}`
      },
      lp1: {
        address: `${lpPair.token1.address}`,
        oracle: "tokens",
        oracleId: `${lpPair.token1.symbol}`,
        decimals: `${lpPair.token1.decimals}`,
      }
    }
  }

  console.log("\nBeefy App object:", outputs.app)
  write(`beefy app object:\n${JSON.stringify(outputs.app)}\n`)
  console.log("\nBeefy API object:", outputs.api)
  write(`beefy api object:\n${JSON.stringify(outputs.api)}\n`)
  
  if(hardhat.network.name !== 'localhost') {

    if (hardhat.network.name == 'bsc') {
      await registerSubsidy(vault.address, deployer);
      await registerSubsidy(strategy.address, deployer);
    }
  
    const verification = {
      strategy: {
        address: strategy.address,
        constructorArguments: Object.values(CONTRACTS.strategy.params),
      },
      vault: {
        address: vault.address,
        constructorArguments: Object.values(CONTRACTS.vault.params),
      }
    }
    await hardhat.run("verify:verify", verification.strategy)
    await hardhat.run("verify:verify", verification.vault)
  }
  
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });