// Usage: npm run deploy:aero <want> -- <network>
const { ethers, network } = require('hardhat');
const { addressBook } = require('@beefyfinance/blockchain-addressbook');
const vaultFactoryArtifact = require('../../artifacts-forge/IVaultFactory.sol/IVaultFactory.json');
const strategyFactoryArtifact = require('../../artifacts-forge/IStrategyFactory.sol/IStrategyFactory.json');
const routerArtifact = require('../../artifacts-forge/IAero.sol/IAeroRouter.json');
const pairArtifact = require('../../artifacts-forge/IAero.sol/IAeroPair.json');
const gaugeArtifact = require('../../artifacts-forge/IAero.sol/IAeroGauge.json');
const registryArtifact = require('../../artifacts-forge/IAero.sol/IAeroFactoryRegistry.json');
const poolFactoryArtifact = require('../../artifacts-forge/IAero.sol/IAeroPoolFactory.json');
const tokenArtifact = require('../../artifacts-forge/IERC20Extended.sol/IERC20Extended.json');
const swapperArtifact = require('../../artifacts-forge/IBeefySwapper.sol/IBeefySwapper.json');
const feeConfigArtifact = require('../../artifacts-forge/IFeeConfig.sol/IFeeConfig.json');
const strategyArtifact = require('../../artifacts-forge/StrategyAero.sol/StrategyAero.json');
const strategyArbArtifact = require('../../artifacts-forge/StrategyAeroArb.sol/StrategyAeroArb.json');
const vaultArtifact = require('../../artifacts-forge/BeefyVaultV7.sol/BeefyVaultV7.json');
const beaconProxyArtifact = require('../../artifacts-forge/BeaconProxy.sol/BeaconProxy.json');

const AERO_ROUTER = '0x0fEf9e88A7b76BCDBF451780C6774FE32965Ee98';
const BEACON_SLOT = '0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50';

function requiredAddress(value, name) {
  if (!ethers.utils.isAddress(value || '') || value === ethers.constants.AddressZero) {
    throw new Error(`Invalid or missing ${name}`);
  }
  return ethers.utils.getAddress(value);
}

function cloneImplementation(code, label) {
  const match = /^0x363d3d373d3d3d363d73([0-9a-f]{40})5af43d82803e903d91602b57fd5bf3$/i.exec(code);
  if (!match) throw new Error(`${label} is not a standard factory clone`);
  return ethers.utils.getAddress('0x' + match[1]);
}

function beaconProxyRuntime(runtime, beacon) {
  let expected = runtime.object.replace(/^0x/, '');
  const refs = Object.values(runtime.immutableReferences || {}).flat();
  if (!refs.length) throw new Error('BeaconProxy artifact lacks immutable references');
  for (const ref of refs) expected = expected.slice(0, ref.start * 2) + ethers.utils.hexZeroPad(beacon, ref.length).slice(2) + expected.slice((ref.start + ref.length) * 2);
  return '0x' + expected;
}

async function main() {
  const [deployer] = await ethers.getSigners();
  if (!deployer) throw new Error('Configure DEPLOYER_PK for the selected Hardhat network');
  const isArbitrumStrategy = [42161, 4663].includes(Number((await ethers.provider.getNetwork()).chainId));
  const selectedStrategyArtifact = isArbitrumStrategy ? strategyArbArtifact : strategyArtifact;
  const beefyfinance = addressBook[network.name]?.platforms?.beefyfinance;
  if (!beefyfinance) throw new Error(`No Beefy address book entry for ${network.name}`);
  const want = requiredAddress(process.env.AERO_WANT, 'pool address');
  const strategist = requiredAddress(process.env.STRATEGIST_ADDRESS, 'STRATEGIST_ADDRESS');
  const pair = await ethers.getContractAt(pairArtifact.abi, want);
  const router = await ethers.getContractAt(routerArtifact.abi, AERO_ROUTER);
  const [kind, token0, token1, poolFactory, registryAddress, output, native, voter] = await Promise.all([
    pair.POOL_TYPE(), pair.token0(), pair.token1(), pair.factory(), router.FACTORY_REGISTRY(),
    router.EMISSION_TOKEN(), router.WETH(), router.LEAF_VOTER(),
  ]);
  let poolType;
  if (kind === ethers.utils.formatBytes32String('V2_STABLE')) poolType = 'stable';
  else if (kind === ethers.utils.formatBytes32String('V2_VOLATILE')) poolType = 'volatile';
  else throw new Error(`Unsupported pool type: ${kind}`);
  const [lp0, lp1] = await Promise.all([ethers.getContractAt(tokenArtifact.abi, token0), ethers.getContractAt(tokenArtifact.abi, token1)]);
  const [symbol0, symbol1] = await Promise.all([lp0.symbol(), lp1.symbol()]);
  if (!symbol0 || !symbol1) throw new Error('Pool token symbols must be nonempty');
  const chain = { optimism: 'OP', base: 'Base', arbitrum: 'Arbitrum', ethereum: 'Ethereum', robinhood: 'Robinhood', arc: 'Arc' }[network.name] || network.name;
  const tokens = `${symbol0}-${symbol1}`;
  const vaultParams = {
    mooName: `Moo Aero V2 ${chain} ${tokens}`,
    mooSymbol: `mooAeroV2${chain}${tokens}`,
    delay: 1,
  };
  const strategyParams = {
    want,
    unirouter: requiredAddress(beefyfinance.beefySwapper, 'beefySwapper'),
    strategist,
    keeper: requiredAddress(beefyfinance.keeper, 'keeper'),
    beefyFeeRecipient: requiredAddress(beefyfinance.beefyFeeRecipient, 'beefyFeeRecipient'),
    beefyFeeConfig: requiredAddress(beefyfinance.beefyFeeConfig, 'beefyFeeConfig'),
    beefyVaultProxy: requiredAddress(beefyfinance.vaultFactory, 'vaultFactory'),
    strategyFactory: requiredAddress(beefyfinance.strategyFactory, 'strategyFactory'),
    strategyImplementationName: process.env.AERO_STRATEGY_NAME || 'Aero',
    vaultOwner: requiredAddress(beefyfinance.vaultOwner, 'vaultOwner'),
  };
  const registry = await ethers.getContractAt(registryArtifact.abi, registryAddress);
  const gaugeAddress = requiredAddress(await registry.targetToGauge(want), 'gauge');
  const gauge = await ethers.getContractAt(gaugeArtifact.abi, gaugeAddress);
  const [isPool, stakingToken, gaugeVoter] = await Promise.all([gauge.isPool(), gauge.stakingToken(), gauge.voter()]);
  if (!isPool || stakingToken.toLowerCase() !== want.toLowerCase() || gaugeVoter.toLowerCase() !== voter.toLowerCase()) {
    throw new Error('Gauge does not match the pool and Aero voter');
  }
  if (output.toLowerCase() === want.toLowerCase() || native.toLowerCase() === want.toLowerCase()) {
    throw new Error('Reward and native tokens must differ from the pool');
  }
  for (const [name, addr] of Object.entries({ output, native, token0, token1, poolFactory, registryAddress,
    gauge: gaugeAddress, swapper: strategyParams.unirouter, feeConfig: strategyParams.beefyFeeConfig,
    vaultFactory: strategyParams.beefyVaultProxy, strategyFactory: strategyParams.strategyFactory })) {
    requiredAddress(addr, name);
    if (await ethers.provider.getCode(addr) === '0x') throw new Error(`${name} has no contract code`);
  }
  const poolFactoryContract = await ethers.getContractAt(poolFactoryArtifact.abi, poolFactory);
  if ((await poolFactoryContract.getPool(token0, token1)).toLowerCase() !== want.toLowerCase()) {
    throw new Error('Pool factory does not resolve the requested pool');
  }
  const swapper = await ethers.getContractAt(swapperArtifact.abi, strategyParams.unirouter);
  for (const [from, to] of [[output, native], [native, token0], [native, token1]]) {
    if (from.toLowerCase() === to.toLowerCase()) continue;
    const route = await swapper.swapInfo(from, to);
    if (route.router === ethers.constants.AddressZero) throw new Error(`Missing Beefy swapper route: ${from} -> ${to}`);
  }
  const feeConfig = await ethers.getContractAt(feeConfigArtifact.abi, strategyParams.beefyFeeConfig);
  async function checkFees(strategy) {
    const fees = await feeConfig.getFees(strategy);
    if (fees.total.gt(ethers.constants.WeiPerEther) || fees.call.add(fees.strategist).gt(ethers.constants.WeiPerEther)) {
      throw new Error('Invalid fee configuration');
    }
  }
  await checkFees(ethers.constants.AddressZero);
  const stratFactory = await ethers.getContractAt(strategyFactoryArtifact.abi, strategyParams.strategyFactory);
  const beacon = requiredAddress(await stratFactory.instances(strategyParams.strategyImplementationName), 'registered Aero beacon');
  const registeredImplementation = requiredAddress(await stratFactory.getImplementation(strategyParams.strategyImplementationName), 'registered Aero implementation');
  const strategyRuntime = typeof selectedStrategyArtifact.deployedBytecode === 'string' ? selectedStrategyArtifact.deployedBytecode : selectedStrategyArtifact.deployedBytecode?.object;
  if (!strategyRuntime || (await ethers.provider.getCode(registeredImplementation)).toLowerCase() !== strategyRuntime.toLowerCase()) {
    throw new Error('Registered Aero implementation does not match the local Forge artifact');
  }
  console.log('Deploying:', vaultParams.mooName);
  console.log(JSON.stringify({ network: network.name, deployer: await deployer.getAddress(), poolType, gauge: gaugeAddress,
    output, native, vaultParams, strategyParams }, null, 2));
  console.log('WARNING: factory proxies are initialized in separate transactions; they can be initialized by another account.');

  const factory = await ethers.getContractAt(vaultFactoryArtifact.abi, strategyParams.beefyVaultProxy);
  const signerAddress = await deployer.getAddress();
  let vault = process.env.AERO_RESUME_VAULT ? requiredAddress(process.env.AERO_RESUME_VAULT, 'AERO_RESUME_VAULT') : undefined;
  let strat = process.env.AERO_RESUME_STRATEGY ? requiredAddress(process.env.AERO_RESUME_STRATEGY, 'AERO_RESUME_STRATEGY') : undefined;
  const same = (a, b) => a.toLowerCase() === b.toLowerCase();
  let existingStrategy;
  let existingVault;
  if (strat) {
    const storedBeacon = await ethers.provider.getStorageAt(strat, BEACON_SLOT);
    if (!same(storedBeacon, ethers.utils.hexZeroPad(beacon, 32))) throw new Error('Resumed strategy beacon does not match the registered Aero beacon');
    const runtime = beaconProxyArtifact.deployedBytecode;
    if (!same(await ethers.provider.getCode(strat), beaconProxyRuntime(runtime, beacon))) throw new Error('Resumed strategy is not the expected BeaconProxy');
    existingStrategy = await ethers.getContractAt(selectedStrategyArtifact.abi, strat, deployer);
    const owner = await existingStrategy.owner();
    if (same(owner, ethers.constants.AddressZero)) {
      if (!vault) throw new Error('An uninitialized resumed strategy requires AERO_RESUME_VAULT');
    } else {
      if (!same(owner, signerAddress)) throw new Error('Resumed strategy is not owned by the deployer');
      const [linkedVault, actualWant, actualGauge, actualOutput, actualNative, unirouter, keeper, strategist, recipient, feeConfig, hod] = await Promise.all([
        existingStrategy.vault(), existingStrategy.want(), existingStrategy.gauge(), existingStrategy.output(), existingStrategy.native(),
        existingStrategy.unirouter(), existingStrategy.keeper(), existingStrategy.strategist(), existingStrategy.beefyFeeRecipient(),
        existingStrategy.beefyFeeConfig(), existingStrategy.harvestOnDeposit(),
      ]);
      if (!vault) vault = requiredAddress(linkedVault, 'strategy vault');
      if (!same(linkedVault, vault) || !same(actualWant, want) || !same(actualGauge, gaugeAddress) ||
          !same(actualOutput, output) || !same(actualNative, native) || !same(unirouter, strategyParams.unirouter) ||
          !same(keeper, strategyParams.keeper) || !same(strategist, strategyParams.strategist) ||
          !same(recipient, strategyParams.beefyFeeRecipient) || !same(feeConfig, strategyParams.beefyFeeConfig) || hod) {
        throw new Error('Resumed strategy configuration does not match');
      }
    }
  }
  if (vault) {
    const impl = cloneImplementation(await ethers.provider.getCode(vault), 'Vault');
    if (!same(impl, await factory.instance())) throw new Error('Vault implementation does not match factory instance');
    existingVault = await ethers.getContractAt(vaultArtifact.abi, vault, deployer);
    const owner = await existingVault.owner();
    if (!same(owner, ethers.constants.AddressZero)) {
      if (!strat) throw new Error('An initialized resumed vault requires AERO_RESUME_STRATEGY');
      if (!same(owner, signerAddress) && !same(owner, strategyParams.vaultOwner)) throw new Error('Unexpected vault owner');
      if (!same(await existingVault.strategy(), strat) || !same(await existingVault.want(), want) ||
          (await existingVault.name()) !== vaultParams.mooName || (await existingVault.symbol()) !== vaultParams.mooSymbol ||
          !(await existingVault.approvalDelay()).eq(vaultParams.delay)) throw new Error('Resumed vault configuration does not match');
    }
  }

  async function clone(label, method, args) {
    const tx = await factory[method](...args);
    console.log(`${label} clone transaction: ${tx.hash}`);
    const receipt = await tx.wait();
    const event = receipt.events?.find(e => e.address.toLowerCase() === factory.address.toLowerCase() && e.event === 'ProxyCreated');
    if (!event) throw new Error(`Missing ProxyCreated event; inspect ${tx.hash}`);
    const addr = requiredAddress(event.args.proxy, label);
    console.log(`${label}: ${addr}`);
    return addr;
  }
  if (!vault) vault = await clone('Vault', 'cloneVault', []);
  if (!strat) {
    const tx = await stratFactory.createStrategy(strategyParams.strategyImplementationName);
    console.log(`Strategy proxy transaction: ${tx.hash}`);
    const receipt = await tx.wait();
    const event = receipt.events?.find(e => e.address.toLowerCase() === stratFactory.address.toLowerCase() && e.event === 'ProxyCreated' && e.args.strategyName === strategyParams.strategyImplementationName);
    if (!event) throw new Error(`Missing strategy ProxyCreated event; inspect ${tx.hash}`);
    strat = requiredAddress(event.args.proxy, 'Strategy');
    console.log(`Strategy: ${strat}`);
  }
  const vaultContract = await ethers.getContractAt(vaultArtifact.abi, vault, deployer);
  const stratContract = await ethers.getContractAt(selectedStrategyArtifact.abi, strat, deployer);
  const vaultArguments = [strat, vaultParams.mooName, vaultParams.mooSymbol, vaultParams.delay];
  const strategyArguments = [want, [vault, strategyParams.unirouter, strategyParams.keeper,
    strategyParams.strategist, strategyParams.beefyFeeRecipient, strategyParams.beefyFeeConfig]];
  async function send(label, promise) {
    const tx = await promise;
    console.log(`${label}: ${tx.hash}`);
    await tx.wait();
  }
  if (same(await stratContract.owner(), ethers.constants.AddressZero)) await send('Initialize strategy', stratContract.initialize(...strategyArguments));
  if (same(await vaultContract.owner(), ethers.constants.AddressZero)) await send('Initialize vault', vaultContract.initialize(...vaultArguments));
  await checkFees(strat);
  if (!same(await vaultContract.owner(), strategyParams.vaultOwner)) await send('Transfer vault ownership', vaultContract.transferOwnership(strategyParams.vaultOwner));
  const [sv, vs, sw, vw, so, vo, hod] = await Promise.all([
    stratContract.vault(), vaultContract.strategy(), stratContract.want(), vaultContract.want(),
    stratContract.owner(), vaultContract.owner(), stratContract.harvestOnDeposit(),
  ]);
  if (sv.toLowerCase() !== vault.toLowerCase() || vs.toLowerCase() !== strat.toLowerCase() ||
      sw.toLowerCase() !== want.toLowerCase() || vw.toLowerCase() !== want.toLowerCase() ||
      so.toLowerCase() !== signerAddress.toLowerCase() ||
      vo.toLowerCase() !== strategyParams.vaultOwner.toLowerCase() || hod) {
    throw new Error('Post-deployment verification failed; inspect the printed transactions');
  }
  console.log('Verified vault, strategy, ownership and harvest-on-deposit configuration.');
}

if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { main, requiredAddress, cloneImplementation, beaconProxyRuntime };
