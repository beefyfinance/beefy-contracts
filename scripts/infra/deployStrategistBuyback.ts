import hardhat, { ethers, upgrades } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { verifyContract } from "../../utils/verifyContract";

const {
  BIFI: { address: BIFI },
  WFTM: { address: WFTM },
} = addressBook.fantom.tokens;
const { spookyswap } = addressBook.fantom.platforms;

const shouldVerifyOnEtherscan = true;

const params = {
  bifiMaxiVaultAddress: "0xbF07093ccd6adFC3dEB259C557b61E94c1F66945",
  unirouter: spookyswap.router,
  nativeToNativeRoute: [WFTM, BIFI],
};

const contractNames = {
  strategistBuyback: "StrategistBuyback",
};

const implementationConstructorArguments: any[] = []; // proxy implementations cannot have constructors

const deployStrategistBuyback = async () => {
  if (Object.values(params).some(v => v === undefined) || Object.values(contractNames).some(v => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const StrategistBuyback = await ethers.getContractFactory(contractNames.strategistBuyback);

  console.log("Deploying:", contractNames.strategistBuyback);

  const constructorArguments = [params.bifiMaxiVaultAddress, params.unirouter, params.nativeToNativeRoute];
  const transparentUpgradableProxy = await upgrades.deployProxy(StrategistBuyback, constructorArguments);
  await transparentUpgradableProxy.deployed();

  const implementationAddress = await upgrades.erc1967.getImplementationAddress(transparentUpgradableProxy.address);

  console.log();
  console.log("TransparentUpgradableProxy:", transparentUpgradableProxy.address);
  console.log(`Implementation address (${contractNames.strategistBuyback}):`, implementationAddress);

  console.log();
  console.log("Running post deployment");

  const verifyContractsPromises: Promise<any>[] = [];
  if (shouldVerifyOnEtherscan) {
    console.log(`Verifying ${contractNames.strategistBuyback}`);
    verifyContractsPromises.push(verifyContract(implementationAddress, implementationConstructorArguments));
  }
  console.log();

  await Promise.all(verifyContractsPromises);
};

deployStrategistBuyback()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
