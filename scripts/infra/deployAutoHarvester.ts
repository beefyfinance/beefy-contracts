import hardhat, { ethers, upgrades } from "hardhat";
import { verifyContract } from "../../utils/verifyContract";

import { addressBook } from "blockchain-addressbook";
import { BigNumber } from "ethers";

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
  const link_oracle_version: string = "0xb0897686c545045aFc77CF20eC7A532E3120E0F1";
  const pegswapAddress: string = "0xAA1DC356dc4B18f30C347798FD5379F3D77ABC5b";
  const gasCap: number = 2500000;
  const gasCapBuffer: number = 100000;
  const harvestGasLimit: number = 600000;
  const shouldConvertToLinkThreshold: BigNumber = ethers.utils.parseEther("1");

  const constructorArguments: any[] = [
    vaultRegistryAddress,
    unirouter,
    nativeToLinkRoute,
    link_oracle_version,
    pegswapAddress,
    gasCap,
    gasCapBuffer,
    harvestGasLimit,
    shouldConvertToLinkThreshold
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
};

deploy()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
