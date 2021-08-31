const fs = require("fs");
const hardhat = require("hardhat");
const { addressBook } = require("blockchain-addressbook");
const { getLpPair, writer, resolveSwapRoute, removeWofWnative, checkIsWnative } = require("../../utils/farms.helpers");
const registerSubsidy = require("../../utils/registerSubsidy");
const predictAddresses = require("../../utils/predictAddresses");

/**
 * Main Variables
 * this all are 'variables' to modify in case use another platform or blockchain
 */
const POOL_ID = process.env.POOL_ID;
const CHAIN_NAME = process.env.CHAIN_NAME || "bsc";

const PLATFORM = {
  name: process.env.PLATFORM_NAME || "PancakeSwap",
  strategy: process.env.PLATFORM_STRATEGY || "StrategyCommonChefLPWithGasThrottler",
  prefix: process.env.PLATFORM_PREFIX || "CakeV2",
  url: process.env.PLATFORM_URL || "exchange.pancakeswap.finance/#/",
  chef: process.env.PLATFORM_CHEF || addressBook.bsc.platforms.pancake.masterchef,
  router: process.env.PLATFORM_ROUTER || addressBook.bsc.platforms.pancake.router,
  tokens: {
    reward: process.env.PLATFORM_TOKEN_REWARD
      ? JSON.parse(process.env.PLATFORM_TOKEN_REWARD)
      : addressBook.bsc.tokens.CAKE,
    wnative: process.env.PLATFORM_TOKEN_WNATIVE
      ? JSON.parse(process.env.PLATFORM_TOKEN_WNATIVE)
      : addressBook.bsc.tokens.WBNB,
  },
};

const CONTRACTS = {
  vault: {
    name: "BeefyVaultV6",
    address: "",
    params: "",
  },
  strategy: {
    name: PLATFORM.strategy || "StrategyCommonChefLP",
    address: "",
    params: "",
  },
};

const { BUSD, USDT, USDC } = addressBook[CHAIN_NAME].tokens;
const proxieTokenAddress = [PLATFORM.tokens.reward, PLATFORM.tokens.wnative, USDT, USDC].map(t => t.address);
if (CHAIN_NAME === "bsc") proxieTokenAddress.push(BUSD.address);

const main = async () => {
  console.log("Platform:", PLATFORM, "\n");
  const deployer = await ethers.getSigner();
  const lpPair = await getLpPair({ poolId: POOL_ID, deployer, chefAddress: PLATFORM.chef, chainName: CHAIN_NAME });

  const write = writer({ dirname: `${__dirname}/logs`, filename: `${hardhat.network.name}-${lpPair.name}` });

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc: hardhat.network.config.url });
  CONTRACTS.vault.address = predictedAddresses.vault;
  CONTRACTS.strategy.address = predictedAddresses.strategy;

  const swapRouteConfig = {
    toLp0Route: {
      input: PLATFORM.tokens.reward.address,
      proxies: proxieTokenAddress,
      preferredProxy: lpPair.token1.address,
      output: lpPair.token0.address,
      wnative: PLATFORM.tokens.wnative.address,
    },
    toLp1Route: {
      input: PLATFORM.tokens.reward.address,
      proxies: proxieTokenAddress,
      preferredProxy: lpPair.token0.address,
      output: lpPair.token1.address,
      wnative: PLATFORM.tokens.wnative.address,
    },
  };

  const KEEPER = process.env.KEEPER || deployer.address;

  CONTRACTS.vault.params = {
    strategy: predictedAddresses.strategy,
    mooName: `Moo ${PLATFORM.prefix} ${lpPair.name}`,
    mooSymbol: `moo${PLATFORM.prefix}${lpPair.name}`,
    delay: 21600,
  };

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

  console.log("Vault:", CONTRACTS.vault, "\n");
  write(`Vault:\n${JSON.stringify(CONTRACTS.vault)}\n`);
  console.log("Strategy", CONTRACTS.strategy, "\n");
  write(`Strategy:\n${JSON.stringify(CONTRACTS.strategy)}\n`);

  if (
    Object.values(CONTRACTS.vault.params).some(v => v === undefined) ||
    Object.values(CONTRACTS.strategy.params).some(v => v === undefined) ||
    CONTRACTS.vault.name === undefined ||
    CONTRACTS.strategy.name === undefined
  ) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory(CONTRACTS.vault.name);
  const Strategy = await ethers.getContractFactory(CONTRACTS.strategy.name);

  console.log(`\n==> Deploying "${CONTRACTS.vault.params.mooName}"`);

  const vault = await Vault.deploy(...Object.values(CONTRACTS.vault.params));
  await vault.deployed();

  const strategy = await Strategy.deploy(...Object.values(CONTRACTS.strategy.params));
  await strategy.deployed();

  console.log("Vault deployed on ", vault.address);
  console.log("Strategy deployed on ", strategy.address);

  const outputs = {
    app: {
      id: `${PLATFORM.prefix.toLocaleLowerCase()}-${lpPair.name.toLowerCase()}`,
      name: `${lpPair.name} LP`,
      token: `${lpPair.name} LP`,
      tokenDescription: `${PLATFORM.name}`,
      tokenAddress: CONTRACTS.strategy.params.want,
      tokenDecimals: Number(`${lpPair.decimals.replace("1e", "")}`),
      tokenDescriptionUrl: "#",
      earnedToken: CONTRACTS.vault.params.mooSymbol,
      earnedTokenAddress: vault.address,
      earnContractAddress: vault.address,
      pricePerFullShare: 1,
      tvl: 0,
      oracle: "lps",
      oracleId: `${PLATFORM.prefix.toLocaleLowerCase()}-${lpPair.name.toLowerCase()}`,
      oraclePrice: 0,
      depositsPaused: false,
      status: "active",
      platform: PLATFORM.name,
      assets: [],
      callFee: 0.5,
      addLiquidityUrl: `https://${PLATFORM.url}/add/${lpPair.token0.address}/${lpPair.token1.address}`,
      buyTokenUrl: `https://${PLATFORM.url}/swap?inputCurrency=${lpPair.token0.address}&outputCurrency=${lpPair.token1.address}`,
    },
    api: {
      name: `${PLATFORM.prefix.toLocaleLowerCase()}-${lpPair.name.toLowerCase()}`,
      address: `${lpPair.address}`,
      decimals: `${lpPair.decimals}`,
      poolId: Number(POOL_ID),
      chainId: 56,
      lp0: {
        address: `${lpPair.token0.address}`,
        oracle: "tokens",
        oracleId: `${lpPair.token0.symbol}`,
        decimals: `${lpPair.token1.decimals}`,
      },
      lp1: {
        address: `${lpPair.token1.address}`,
        oracle: "tokens",
        oracleId: `${lpPair.token1.symbol}`,
        decimals: `${lpPair.token1.decimals}`,
      },
    },
    pr: `
    ${CONTRACTS.vault.params.mooSymbol}
    Vault: https://bscscan.com/address/${CONTRACTS.vault.address}#code
    Strategy: https://bscscan.com/address/${CONTRACTS.strategy.address}#code
    Beefy API PR:`,
  };

  if (checkIsWnative(lpPair.token0.symbol, CHAIN_NAME)) {
    outputs.app.assets = [lpPair.token1.symbol, removeWofWnative(lpPair.token0.symbol, CHAIN_NAME)];
  } else {
    outputs.app.assets = [lpPair.token0.symbol, removeWofWnative(lpPair.token1.symbol, CHAIN_NAME)];
  }

  console.log("\nBeefy APP object:", outputs.app);
  write(`Beefy app object:\n${JSON.stringify(outputs.app)}\n`);
  console.log("\nBeefy API object:", outputs.api);
  write(`Beefy api object:\n${JSON.stringify(outputs.api)}\n`);
  console.log("\nBeefy APP PR message:\n", outputs.pr);
  write(`\nBeefy APP PR:\n${JSON.stringify(outputs.pr)}\n`);

  if (hardhat.network.name !== "localhost") {
    if (hardhat.network.name == "bsc") {
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
      },
    };
    await hardhat.run("verify:verify", verification.strategy);
    await hardhat.run("verify:verify", verification.vault);
  }
};

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
