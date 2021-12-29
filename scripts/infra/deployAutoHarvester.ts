import hardhat, { ethers, upgrades } from "hardhat";
import { verifyContract } from "../../utils/verifyContract";

import { addressBook } from "blockchain-addressbook";
import { BigNumber, ContractFactory } from "ethers";
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

const shouldVerifyOnEtherscan = false;
const isProxy = false;

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
      shouldSwapToLinkThreshold: ethers.utils.parseEther("1"),
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

  const { keeperRegistry, upkeepId, unirouter, nativeToLinkRoute, oracleLink, pegswap, shouldSwapToLinkThreshold } =
    config.upkeepRefunder.args;

  const refunderConstructorArguments: any[] = [
    keeperRegistry,
    upkeepId,
    unirouter,
    nativeToLinkRoute,
    oracleLink,
    pegswap,
    shouldSwapToLinkThreshold,
  ];

  const contractInfo = await deployContract(
    config.upkeepRefunder.contractName,
    isProxy,
    UpkeepRefunder,
    refunderConstructorArguments
  );

  const verifyContractsPromises: Promise<any>[] = [];
  if (shouldVerifyOnEtherscan) {
    console.log(`Verifying ${config.upkeepRefunder.contractName}`);
    verifyContractsPromises.push(verifyContract(contractInfo.impl, implementationConstructorArguments));
  }
  console.log();

  await Promise.all(verifyContractsPromises);

  // const upkeepRefunder = (await ethers.getContractAt(
  //   config.upkeepRefunder.contractName,
  //   refunderProxy.address
  // )) as unknown as UpkeepRefunder;

  // Manually reset upkeep id if needed

  return {
    upkeepAddress: contractInfo.contract,
  };
};

const deployHarvester = async (upkeepAddress: string) => {
  const BeefyHarvesterFactory = await ethers.getContractFactory(config.harvester.contractName);

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

  const contractInfo = await deployContract(
    config.harvester.contractName,
    isProxy,
    BeefyHarvesterFactory,
    harvesterConstructorArguments
  );

  const verifyContractsPromises: Promise<any>[] = [];
  if (shouldVerifyOnEtherscan) {
    console.log(`Verifying ${config.harvester.contractName}`);
    verifyContractsPromises.push(verifyContract(contractInfo.impl, implementationConstructorArguments));
  }
  console.log();

  await Promise.all(verifyContractsPromises);

  console.log("Setting upkeep address.");

  const autoHarvester = (await ethers.getContractAt(
    config.harvester.contractName,
    contractInfo.contract
  )) as unknown as BeefyHarvester;

  const chainlinkUpkeeper: string = "0x7b3EC232b08BD7b4b3305BE0C044D907B2DF960B"; // TODO: move this to address book
  await autoHarvester.setUpkeepers([chainlinkUpkeeper], true);
};

const deployContract = async (
  name: string,
  isProxy: boolean,
  contractFactory: ContractFactory,
  constructorArgs: any[]
): Promise<{ contract: string; impl: string }> => {
  console.log("Deploying:", name);

  const ret = {
    contract: "",
    impl: "",
  };

  if (isProxy) {
    const proxy = await upgrades.deployProxy(contractFactory, constructorArgs);
    await proxy.deployed();

    const implementationAddress = await upgrades.erc1967.getImplementationAddress(proxy.address);

    console.log();
    console.log(`Proxy ${proxy.address}`);
    console.log(`Implementation address (${name}): ${implementationAddress}`);

    ret.contract = proxy.address;
    ret.impl = implementationAddress;
  } else {
    const deployTx = await contractFactory.deploy();
    await deployTx.deployed();

    console.log();
    console.log(`${name}: ${deployTx.address}`);

    console.log(`Running initialize()`);

    const contract = await ethers.getContractAt(name, deployTx.address);

    contract.initialize(...constructorArgs);

    ret.contract = contract.address;
  }

  return ret;
};

deploy()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
