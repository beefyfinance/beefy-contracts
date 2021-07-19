const hardhat = require("hardhat");

const ERC20ABI = require("../../../data/abi/ERC20.json");
const masterchefABI = require("../../../data/abi/SushiMasterChef.json");
const LPPairABI = require("../../../data/abi/UniswapLPPair.json");

const registerSubsidy = require("../../../utils/registerSubsidy");
const predictAddresses = require("../../../utils/predictAddresses");
const getNetworkRpc = require("../../../utils/getNetworkRpc");
const { addressBook } = require("blockchain-addressbook")
const { CAKE, WBNB, BUSD, USDT } = addressBook.bsc.tokens;
const baseTokenAddresses = [CAKE, WBNB, BUSD, USDT].map(t => t.address);

const ethers = hardhat.ethers;
const rpc = getNetworkRpc(hardhat.network.name);

const poolId = parseInt(process.argv[2], 10);
if (poolId < 1) {
  throw Error('Usage: Need to pass a poolId as argument.');
}

async function main() {
  const deployer = await ethers.getSigner();
  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

  const masterchefContract = new ethers.Contract(addressBook.bsc.platforms.pancake.masterchef, masterchefABI, deployer);
  const poolInfo = await masterchefContract.poolInfo(poolId);
  const lpAddress = ethers.utils.getAddress(poolInfo.lpToken);

  const lpContract = new ethers.Contract(lpAddress, LPPairABI, deployer);
  const lpPair = {
    address: lpAddress,
    token0: {
      address: await lpContract.token0(),
      symbol: ''
    },
    token1: {
      address: await lpContract.token1(),
      symbol: ''
    },
    decimals: await lpContract.decimals(),
  };

  const token0Contract = new ethers.Contract(lpPair.token0, ERC20ABI, deployer);
  lpPair.token0.symbol = await token0Contract.symbol();
  
  const token1Contract = new ethers.Contract(lpPair.token1, ERC20ABI, deployer);
  lpPair.token1.symbol = await token1Contract.symbol();

  const resolveSwapRoute = (input, proxies, preferredProxy, output) => {
    if ([lpPair.token0.address, lpPair.token1.address].includes(WBNB.address)) { // Native pair
      if (output === WBNB.address) return [WBNB.address];
      return [WBNB.address, output];
    }

    if (input === output) return [input];
    if (proxies.includes(output)) return [input, output];
    if (proxies.includes(preferredProxy)) return [input, preferredProxy, output];
    return [input, proxies.filter(input)[0], output]; // TODO: Choose the best proxy
  }

  const mooPairName = `${lpPair.token0.symbol}-${lpPair.token1.symbol}`;

  const vaultParams = {
    strategy: predictedAddresses.strategy,
    mooName: `Moo CakeV2 ${mooPairName}`,
    mooSymbol: `mooCakeV2${mooPairName}`,
    delay: 21600,
  }

  const strategyParams = {
    want: lpPair.address,
    poolId: poolId,
    chefAddress: addressBook.bsc.platforms.pancake.masterchef,
    vault: predictedAddresses.vault,
    unirouter: addressBook.bsc.platforms.pancake.router, // Pancakeswap Router V2
    keeper: addressBook.bsc.platforms.beefyfinance.keeper,
    strategist: deployer.address, // your address for rewards
    beefyFeeRecipient: addressBook.bsc.platforms.beefyfinance.beefyFeeRecipient,
    toNativeRoute: [CAKE.address, WBNB.address],
    toLp0Route: resolveSwapRoute(CAKE.address, baseTokenAddresses, lpPair.token1, lpPair.token0),
    toLp1Route: resolveSwapRoute(CAKE.address, baseTokenAddresses, lpPair.token0, lpPair.token1),
  };

  const contractNames = {
    vault: "BeefyVaultV6",
    strategy: "StrategyCommonChefLP"
  }

  console.log({vaultParams, strategyParams, contractNames});

  if (Object.values(vaultParams).some((v) => v === undefined) || Object.values(strategyParams).some((v) => v === undefined) || Object.values(contractNames).some((v) => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory(contractNames.vault);
  const Strategy = await ethers.getContractFactory(contractNames.strategy);

  console.log("Deploying:", vaultParams.mooName);

  const vault = await Vault.deploy(...Object.values(vaultParams));
  await vault.deployed();

  const strategy = await Strategy.deploy(...Object.values(strategyParams));
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);
  console.log("Beefy App object:", {
    id: `cakev2-${mooPairName.toLowerCase()}`,
    name: `${mooPairName} LP`,
    token: `${mooPairName} LP2`,
    tokenDescription: 'PancakeSwap',
    tokenAddress: strategyParams.want,
    tokenDecimals: lpPair.decimals,
    tokenDescriptionUrl: '#',
    earnedToken: vaultParams.mooSymbol,
    earnedTokenAddress: vault.address,
    earnContractAddress: vault.address,
    pricePerFullShare: 1,
    tvl: 0,
    oracle: 'lps',
    oracleId: `cakev2-${mooPairName.toLowerCase()}`,
    oraclePrice: 0,
    depositsPaused: false,
    status: 'active',
    platform: 'PancakeSwap',
    assets: [lpPair.token0.symbol, lpPair.token1.symbol],
    callFee: 0.5,
    addLiquidityUrl:
      `https://exchange.pancakeswap.finance/#/add/${lpPair.token0.address}/${lpPair.token1.address}`,
    buyTokenUrl:
      `https://exchange.pancakeswap.finance/#/swap?inputCurrency=${lpPair.token0.address}&outputCurrency=${lpPair.token1.address}`,
  });

  await registerSubsidy(vault.address, deployer);
  await registerSubsidy(strategy.address, deployer);

  const strategyVerificationArgs = {
    address: strategy.address,
    constructorArguments: Object.values(strategyParams),
  }

  const vaultVerificationArgs = {
    address: vault.address,
    constructorArguments: Object.values(vaultParams),
  }

  await hardhat.run("verify:verify", strategyVerificationArgs)
  await hardhat.run("verify:verify", vaultVerificationArgs)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });