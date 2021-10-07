import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";
import { setCorrectCallFee } from "../../utils/setCorrectCallFee";
import { setPendingRewardsFunctionName } from "../../utils/setPendingRewardsFunctionName";
import { verifyContracts } from "../../utils/verifyContracts";

const {
    SUSHI: { address: SUSHI },
    WMATIC: { address: WMATIC },
    FOX: { address: FOX },
    ETH: { address: ETH },
} = addressBook.polygon.tokens;
const { sushi, beefyfinance } = addressBook.polygon.platforms;

const shouldVerifyOnEtherscan = true;

const want = web3.utils.toChecksumAddress("0x93ef615f1ddd27d0e141ad7192623a5c45e8f200");

const vaultParams = {
    mooName: "Moo Sushi FOX-WETH",
    mooSymbol: "mooSushiFOX-WETH",
    delay: 21600,
};

const strategyParams = {
    want,
    poolId: 40,
    chef: sushi.minichef,
    unirouter: sushi.router,
    strategist: "0x715beae184768766c65d8ed4aa6d1f6893efb542", // some address
    keeper: beefyfinance.keeper,
    beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
    outputToNativeRoute: [SUSHI, WMATIC],
    rewardToOutput: [WMATIC, SUSHI],
    outputToLp0Route: [SUSHI, WMATIC, FOX],
    outputToLp1Route: [SUSHI, ETH],
};

const contractNames = {
    vault: "BeefyVaultV6",
    strategy: "StrategyMiniChefLP",
};

async function main() {
    if (
        Object.values(vaultParams).some(v => v === undefined) ||
        Object.values(strategyParams).some(v => v === undefined) ||
        Object.values(contractNames).some(v => v === undefined)
    ) {
        console.error("one of config values undefined");
        return;
    }
    //
    // await hardhat.run("compile");
    //
    // const Vault = await ethers.getContractFactory(contractNames.vault);
    // const Strategy = await ethers.getContractFactory(contractNames.strategy);
    //
    // const [deployer] = await ethers.getSigners();
    //
    // console.log("Deploying:", vaultParams.mooName);
    //
    // const predictedAddresses = await predictAddresses({ creator: deployer.address });
    //
    const vaultConstructorArguments = [
        '0x9acf3e2BdDeBba68267d48FB35BD919407432A8F',
        vaultParams.mooName,
        vaultParams.mooSymbol,
        vaultParams.delay,
    ];
    // const vault = await Vault.deploy(...vaultConstructorArguments);
    // await vault.deployed();

    const strategyConstructorArguments = [
        strategyParams.want,
        strategyParams.poolId,
        strategyParams.chef,
        '0x91F88Edece02dbf868fc37D0a4621b82023b6504',
        strategyParams.unirouter,
        strategyParams.keeper,
        strategyParams.strategist,
        strategyParams.beefyFeeRecipient,
        strategyParams.outputToNativeRoute,
        strategyParams.rewardToOutput,
        strategyParams.outputToLp0Route,
        strategyParams.outputToLp1Route,
    ];
    // const strategy = await Strategy.deploy(...strategyConstructorArguments);
    // await strategy.deployed();


    if (shouldVerifyOnEtherscan) {
        console.log('verifying')
        await verifyContracts( vaultConstructorArguments, strategyConstructorArguments);
    }
    // await setCorrectCallFee(strategy, hardhat.network.name);
    console.log();

    // if (hardhat.network.name === "bsc") {
    //   await registerSubsidy(vault.address, deployer);
    //   await registerSubsidy(strategy.address, deployer);
    // }
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
