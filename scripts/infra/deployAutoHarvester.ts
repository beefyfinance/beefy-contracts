import hardhat, { ethers, upgrades } from "hardhat";
import { verifyContract } from "../../utils/verifyContract";

import { addressBook } from "blockchain-addressbook";
import { BigNumber } from "ethers";
import { BeefyAutoHarvester } from "../../typechain-types";

const chainName = "polygon";
const chainData = addressBook[chainName];

const shouldVerifyOnEtherscan = true;

const contractNames = {
  BeefyAutoHarvester: "BeefyAutoHarvester",
};

const implementationConstructorArguments: any[] = []; // proxy implementations cannot have constructors

const deploy = async () => {
  const BeefyAutoHarvesterFactory = await ethers.getContractFactory(contractNames.BeefyAutoHarvester);

  console.log("Deploying:", contractNames.BeefyAutoHarvester);

  const vaultRegistryAddress = chainData.platforms.beefyfinance.vaultRegistry;
  const unirouter = chainData.platforms.quickswap.router;
  const { WMATIC, ETH, LINK } = chainData.tokens;
  const nativeToLinkRoute: string[] = [WMATIC.address, ETH.address, LINK.address];
  const oracleLink: string = "0xb0897686c545045aFc77CF20eC7A532E3120E0F1";
  const pegswapAddress: string = "0xAA1DC356dc4B18f30C347798FD5379F3D77ABC5b";
  const keeperRegistryAddress: string = "0x7b3EC232b08BD7b4b3305BE0C044D907B2DF960B";
  const gasCap: number = 2500000;
  const gasCapBuffer: number = 100000;
  const harvestGasLimit: number = 600000;
  const shouldConvertToLinkThreshold: BigNumber = ethers.utils.parseEther("1");
  const keeperRegistryGasOverhead: number = 80000;
  const managerProfitabilityBuffer: BigNumber = ethers.utils.parseUnits("0.05", "gwei");

  const constructorArguments: any[] = [
    vaultRegistryAddress,
    keeperRegistryAddress,
    unirouter,
    nativeToLinkRoute,
    oracleLink,
    pegswapAddress,
    gasCap,
    gasCapBuffer,
    harvestGasLimit,
    shouldConvertToLinkThreshold,
    keeperRegistryGasOverhead,
    managerProfitabilityBuffer
  ];
  const transparentUpgradableProxy = await upgrades.deployProxy(BeefyAutoHarvesterFactory, constructorArguments);
  await transparentUpgradableProxy.deployed();

  const implementationAddress = await upgrades.erc1967.getImplementationAddress(transparentUpgradableProxy.address);

  console.log();
  console.log("TransparentUpgradableProxy:", transparentUpgradableProxy.address);
  console.log(`Implementation address (${contractNames.BeefyAutoHarvester}):`, implementationAddress);

  console.log();
  console.log("Running post deployment");

  const verifyContractsPromises: Promise<any>[] = [];
  if (shouldVerifyOnEtherscan) {
    console.log(`Verifying ${contractNames.BeefyAutoHarvester}`);
    verifyContractsPromises.push(verifyContract(implementationAddress, implementationConstructorArguments));
  }
  console.log();

  await Promise.all(verifyContractsPromises);

  console.log("Setting upkeep address.")

  const autoHarvester = (await ethers.getContractAt(
    contractNames.BeefyAutoHarvester,
    transparentUpgradableProxy.address
  )) as unknown as BeefyAutoHarvester;

  const chainlinkUpkeeper: string = "0x7b3EC232b08BD7b4b3305BE0C044D907B2DF960B"; // TODO: move this to address book
  await autoHarvester.setUpkeepers([chainlinkUpkeeper], true);

  // don't forget to set upkeepId once registered.
};

deploy()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
