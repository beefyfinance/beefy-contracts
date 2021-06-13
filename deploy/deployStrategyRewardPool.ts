import hre from "hardhat";
import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";

import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction, DeployOptions } from 'hardhat-deploy/types';

import "../utils/registerSubsidy";
import "../utils/hardhatRPC";
import { contractAddressGenerator } from "../utils/predictAddresses";

import vaults from "../deployData/LpRewardPool";
import { addressBook, ChainId } from "blockchain-addressbook";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";

const VAULT_CONTRACT = "BeefyVaultV6";
const STRAT_CONTRACT = "StrategyCommonRewardPoolLP";

function getVaultDeployOptions(deployer: SignerWithAddress, contract: string, args:any) {
    return {
        from: deployer.address,
        contract: contract,
        args: [args.strategy, args.mooName, args.mooSymbol, args.delay],
        skipIfAlreadyDeployed: true,
        log: true
    } as DeployOptions;
}

function getStratDeployOptions(deployer: SignerWithAddress, contract: string, args:any) {
    return {
        from: deployer.address,
        contract: contract,
        args: [
            args.want,
            args.rewardPool,
            args.vault,
            args.unirouter,
            args.keeper,
            args.strategist,
            args.beefyFeeRecipient,
            args.outputToNativeRoute,
            args.outputToLp0Route,
            args.outputToLp1Route
        ],
        skipIfAlreadyDeployed: true,
        log: true
    } as DeployOptions;
}

const deployAllVaults: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deploy, execute, read, fetchIfDifferent } = hre.deployments;

    const deployer = await hre.ethers.getNamedSigner('deployer');
    console.log(`Deployer: ${deployer.address}\n`);

    for (let vault in vaults) {
        let config = vaults[vault];
        if (config.chainId != hre.network.config.chainId) continue;

        let beefyfinance = addressBook[ChainId[config.chainId]].platforms.beefyfinance;

        let contractAddress = await contractAddressGenerator(deployer);

        let mooName = `Moo ${config.platform} ${config.lp0.symbol}-${config.lp1.symbol}`;
        let mooSymbol = `moo${config.platform}${config.lp0.symbol}-${config.lp1.symbol}`;
        let vaultName = `${mooName} Vault`;
        let stratName = `${mooName} Strategy`

        let vaultParams = {
            strategy: null as string | null,
            mooName: mooName,
            mooSymbol: mooSymbol,
            delay: 21600,
        }

        let strategyParams = {
            want: config.want,
            rewardPool: config.rewardPool,
            vault: null as string | null,
            unirouter: config.unirouter,
            strategist: config.strategist,
            keeper: beefyfinance.keeper,
            beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
            outputToNativeRoute: config.outputToNativeRoute,
            outputToLp0Route: config.outputToLp0Route,
            outputToLp1Route: config.outputToLp1Route,
        };

        let deployedVault = await hre.deployments.getOrNull(vaultName);
        let deployedStrat = await hre.deployments.getOrNull(stratName);

        if (deployedVault && deployedStrat) {
            vaultParams.strategy = deployedVault.address;
            strategyParams.vault = deployedStrat.address;
        }

        let vaultDeployOptions = getVaultDeployOptions(deployer, VAULT_CONTRACT, vaultParams);
        let stratDeployOptions = getStratDeployOptions(deployer, STRAT_CONTRACT, strategyParams);

        if ((await fetchIfDifferent(vaultName, vaultDeployOptions)).differences
            || (await fetchIfDifferent(stratName, stratDeployOptions)).differences
        ) {
            vaultParams.strategy = (await contractAddress.next()).value as string;
            strategyParams.vault = (await contractAddress.next()).value as string;
            vaultDeployOptions = getVaultDeployOptions(deployer, VAULT_CONTRACT, vaultParams);
            stratDeployOptions = getStratDeployOptions(deployer, STRAT_CONTRACT, strategyParams);
        }

        const vaultDeployResult = await deploy(vaultName, vaultDeployOptions);
        const stratDeployResult = await deploy(stratName, stratDeployOptions);
    }
};
export default deployAllVaults;