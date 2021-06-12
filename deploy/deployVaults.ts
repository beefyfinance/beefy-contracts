import hre from "hardhat";
import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";

import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction, DeployOptions } from 'hardhat-deploy/types';

import "../utils/registerSubsidy";
import "../utils/hardhatRPC";
import { contractAddressGenerator } from "../utils/predictAddresses";

import vaults from "../vaults.json";
import { addressBook } from "blockchain-addressbook";
import rpc from "../utils/hardhatRPC";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
const { miMATIC: { address: miMATIC }, USDC: { address: USDC }, QUICK: { address: QUICK }, WMATIC: { address: WMATIC }, ETH: { address: ETH } } = addressBook.polygon.tokens;
const { quickswap, beefyfinance } = addressBook.polygon.platforms;

function getVaultDeployOptions(deployer: SignerWithAddress, contract: String, args:any) {
    return {
        from: deployer.address,
        contract: contract,
        args: [args.strategy, args.mooName, args.mooSymbol, args.delay],
        skipIfAlreadyDeployed: true,
        log: true
    } as DeployOptions;
}

function getStratDeployOptions(deployer: SignerWithAddress, contract: String, args:any) {
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
        let contractAddress = await contractAddressGenerator(deployer);

        let mooName = `Moo ${config.platform} ${config.lp0.name}-${config.lp1.name}`;
        let mooSymbol = `moo${config.platform}${config.lp0.name}-${config.lp1.name}`;
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

        let vaultDeployOptions = getVaultDeployOptions(deployer, config.vaultContract, vaultParams);
        let stratDeployOptions = getStratDeployOptions(deployer, config.strategyContract, strategyParams);

        if ((await fetchIfDifferent(vaultName, vaultDeployOptions)).differences
            || (await fetchIfDifferent(stratName, stratDeployOptions)).differences
        ) {
            vaultParams.strategy = (await contractAddress.next()).value as string;
            strategyParams.vault = (await contractAddress.next()).value as string;
            vaultDeployOptions = getVaultDeployOptions(deployer, config.vaultContract, vaultParams);
            stratDeployOptions = getStratDeployOptions(deployer, config.strategyContract, strategyParams);
        }

        const vaultDeployResult = await deploy(vaultName, vaultDeployOptions);
        const stratDeployResult = await deploy(stratName, stratDeployOptions);

        // if (!vaultDeployResult.newlyDeployed) {
        //     let curStrat = await read(vaultName, 'strategy');
        //     if (curStrat != stratDeployResult.address) {
        //         let stratCandidate = await read(vaultName, 'stratCandidate');
        //         if (stratCandidate.implementation != stratDeployResult.address) {
        //             await execute(vaultName, { from: deployer.address }, 'proposeStrat', stratDeployResult.address);
        //         }
        //         if ('dev' in hre.network.tags) {
        //             let delay = await read(vaultName, 'approvalDelay');
        //             let block = await rpc.getBlockByNumber(hre.network.provider, rpc.BlockTag.Latest, false);
        //             let upgradeTime = stratCandidate.proposedTime + delay + 1;
        //             if (block.header.timestamp.toNumber() < upgradeTime)
        //                 await rpc.setNextBlockTimestamp(hre.network.provider, upgradeTime);
        //             await execute(vaultName, { from: deployer.address }, 'upgradeStrat');
        //         }
        //     }
        // }

        // if ('dev' in hre.network.tags) {
        //     if (vaultDeployResult.newlyDeployed) {
        //         await execute(vaultName, { from: deployer.address }, 'transferOwnership', beefyfinance.vaultOwner);
        //     }
        //     if (stratDeployResult.newlyDeployed) {
        //         await execute(stratName, { from: deployer.address }, 'transferOwnership', beefyfinance.vaultOwner);
        //     }
        // }
    }
};
export default deployAllVaults;