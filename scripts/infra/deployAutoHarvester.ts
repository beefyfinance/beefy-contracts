import hardhat, { ethers, upgrades } from "hardhat";
import { verifyContract } from "../../utils/verifyContract";

import { addressBook } from "blockchain-addressbook";
import { BigNumber } from "ethers";
import { BeefyHarvester, UpkeepRefunder } from "../../typechain-types";

const chainName = "polygon";
const chainData = addressBook[chainName];
const {
  tokens: {
    WNATIVE: { address: WMATIC },
    ETH: { address: ETH },
    LINK: { address: LINK },
  },
} = chainData;

const shouldVerifyOnEtherscan = true;

const keeperRegistry = "0x7b3EC232b08BD7b4b3305BE0C044D907B2DF960B";

const config = {
  harvester: {
    contractName: "BeefyHarvester",
    args: {
      vaultRegistry: chainData.platforms.beefyfinance.vaultRegistry,
      keeperRegistry,
      performUpkeepGasLimit: 2500000,
      performUpkeepGasLimitBuffer: 100000,
      vaultHarvestFunctionGasOverhead: 600000,
      keeperRegistryGasOverhead: 80000,
    },
  },
  upkeepRefunder: {
    contractName: "UpkeepRefunder",
    args: {
      keeperRegistry,
      upkeepId: 24, // TODO: Reset this after deployment if needed
      unirouter: chainData.platforms.quickswap.router,
      nativeToLinkRoute: [WMATIC, ETH, LINK],
      oracleLink: "0xb0897686c545045aFc77CF20eC7A532E3120E0F1",
      pegswap: "0xAA1DC356dc4B18f30C347798FD5379F3D77ABC5b",
      shouldSwapToLinkThreshold: ethers.utils.parseEther("1")
    },
  },
};

const implementationConstructorArguments: any[] = []; // proxy implementations cannot have constructors

const deploy = async () => {
  const { upkeepAddress } = await deployUpkeepRefunder();
  await deployHarvester(upkeepAddress);
};

const deployUpkeepRefunder = async (): Promise<{ upkeepAddress: string }> => {
  const UpkeepRefunder = await ethers.getContractFactory(config.upkeepRefunder.contractName);

  console.log("Deploying:", config.upkeepRefunder.contractName);

  const {
    keeperRegistry,
    upkeepId,
    unirouter,
    nativeToLinkRoute,
    oracleLink,
    pegswap,
    shouldSwapToLinkThreshold
  } = config.upkeepRefunder.args

  const refunderConstructorArguments: any[] = [
    keeperRegistry,
    upkeepId,
    unirouter,
    nativeToLinkRoute,
    oracleLink,
    pegswap,
    shouldSwapToLinkThreshold
  ]

  const refunderProxy = await upgrades.deployProxy(UpkeepRefunder, refunderConstructorArguments);
  await refunderProxy.deployed();

  const implementationAddress = await upgrades.erc1967.getImplementationAddress(refunderProxy.address);

  console.log();
  console.log("Refunder proxy:", refunderProxy.address);
  console.log(`Refunder implementation address (${config.upkeepRefunder.contractName}):`, implementationAddress);

  console.log();
  console.log("Running post deployment");

  const verifyContractsPromises: Promise<any>[] = [];
  if (shouldVerifyOnEtherscan) {
    console.log(`Verifying ${config.upkeepRefunder.contractName}`);
    verifyContractsPromises.push(verifyContract(implementationAddress, implementationConstructorArguments));
  }
  console.log();

  await Promise.all(verifyContractsPromises);

  // const upkeepRefunder = (await ethers.getContractAt(
  //   config.upkeepRefunder.contractName,
  //   refunderProxy.address
  // )) as unknown as UpkeepRefunder;

  // Manually reset upkeep id if needed

  return { 
    upkeepAddress: refunderProxy.address
  };
};

const deployHarvester = async (upkeepAddress: string) => {
  const BeefyHarvesterFactory = await ethers.getContractFactory(config.harvester.contractName);

  console.log("Deploying:", config.harvester.contractName);

  const {
    vaultRegistry,
    keeperRegistry,
    performUpkeepGasLimit,
    performUpkeepGasLimitBuffer,
    vaultHarvestFunctionGasOverhead,
    keeperRegistryGasOverhead,
  } = config.harvester.args;

  const harvesterConstructorArguments: any[] = [
    vaultRegistry,
    keeperRegistry,
    upkeepAddress,
    performUpkeepGasLimit,
    performUpkeepGasLimitBuffer,
    vaultHarvestFunctionGasOverhead,
    keeperRegistryGasOverhead,
  ];
  const harvesterProxy = await upgrades.deployProxy(BeefyHarvesterFactory, harvesterConstructorArguments);
  await harvesterProxy.deployed();

  const implementationAddress = await upgrades.erc1967.getImplementationAddress(harvesterProxy.address);

  console.log();
  console.log("Harvester proxy:", harvesterProxy.address);
  console.log(`Harvester implementation address (${config.harvester.contractName}):`, implementationAddress);

  console.log();
  console.log("Running post deployment");

  const verifyContractsPromises: Promise<any>[] = [];
  if (shouldVerifyOnEtherscan) {
    console.log(`Verifying ${config.harvester.contractName}`);
    verifyContractsPromises.push(verifyContract(implementationAddress, implementationConstructorArguments));
  }
  console.log();

  await Promise.all(verifyContractsPromises);

  console.log("Setting upkeep address.");

  const autoHarvester = (await ethers.getContractAt(
    config.harvester.contractName,
    harvesterProxy.address
  )) as unknown as BeefyHarvester;

  const chainlinkUpkeeper: string = "0x7b3EC232b08BD7b4b3305BE0C044D907B2DF960B"; // TODO: move this to address book
  await autoHarvester.setUpkeepers([chainlinkUpkeeper], true);
};

deploy()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
