require('dotenv');
const hardhat = require('hardhat');
const { ethers } = require('hardhat');
const { addressBook } = require("blockchain-addressbook");
const { writer } = require('../../../utils/farms.helpers')
const { zapNativeToToken, getVaultWant, getUnirouterData } = require("../../../utils/testHelpers");
const { delay } = require("../../../utils/timeHelpers");

/**
 * As Beefy says:
 * manual testing be cause we are stupid
 * 1. Deposit a little in to make sure it works (and to not lose a lot of funds if you cant withdraw).
 * 2. Withdraw all
 * 3. Deposit again wait 30 seconds to a minute and harvest
 * 4. Panic the vault
 * 5. Withdraw 50% while panicked to make sure users can leave
 * 6. Try to deposit, you should get an error, dont send it through just make sure it pops up.
 * 7. Unpause the vault
 * 8. Deposit the 50% you withdrew and harvest again
 * 9. Transfer ownership to multisig (on bsc). The addresses for the owner are in the address book in the api for each chain.
 * After this is done then you can submit a PR for the app and we'll review to have it go live
 */

const GAS_CONFIG = { gasPrice: ethers.utils.parseUnits('5','gwei'), gasLimit: 1e6 }

const CHAIN_NAME = process.env.CHAIN_NAME || "bsc";

const config = {
    vault: {
        address: process.env.VAULT_ADDRESS || `0x2c7926bE88b20Ecb14b1FcB929549bc8Fc8F9905`,
        name: process.env.VAULT_NAME || "BeefyVaultV6",
    },
    strategy: {
        name: process.env.STRATEGY_NAME || "StrategyCommonChefLP",
    },
    testAmount: ethers.utils.parseEther("0.001"),
    wnative: process.env.WNATIVE || addressBook[CHAIN_NAME].tokens.WNATIVE.address,
};

const main = async () => {
    try {
        let write = writer({ dirname: `${__dirname}/outputs`, filename: `manual-test-${hardhat.network.name}-${config.vault.name}` })
        let [deployer, keeper] = await ethers.getSigners();

        vault = await ethers.getContractAt(config.vault.name, config.vault.address);
        const strategyAddr = await vault.strategy();
        strategy = await ethers.getContractAt(config.strategy.name, strategyAddr);

        const unirouterAddr = await strategy.unirouter();
        const unirouterData = getUnirouterData(unirouterAddr);
        unirouter = await ethers.getContractAt(unirouterData.interface, unirouterAddr);
        want = await getVaultWant(vault, config.wnative);

        await zapNativeToToken({
            amount: config.testAmount,
            want,
            nativeTokenAddr: config.wnative,
            unirouter,
            swapSignature: unirouterData.swapSignature,
            recipient: deployer.address,
        });
        let littleAmount = ethers.utils.parseUnits('1000', 'gwei');

        console.log('1. Deposit a little in to make sure it works (and to not lose a lot of funds if you cant withdraw).');
        write('1. Deposit a little in to make sure it works (and to not lose a lot of funds if you cant withdraw).\n');
        await want.approve(vault.address, littleAmount, GAS_CONFIG);
        let tx1 = await vault.deposit(littleAmount, GAS_CONFIG);
        write(`tx1:\t${JSON.stringify(tx1)}\n`)
        
        console.log('2. Withdraw all.')
        write('2. Withdraw all.\n')
        let tx2 = await vault.withdrawAll(GAS_CONFIG)
        write(`tx2:\t${JSON.stringify(tx2)}\n`)
        
        console.log('3. Deposit again wait 30 seconds to a minute and harvest.');
        write('3. Deposit again wait 30 seconds to a minute and harvest.\n');
        await want.approve(vault.address, littleAmount, GAS_CONFIG);
        let tx3a = await vault.deposit(littleAmount, GAS_CONFIG);
        write(`tx3a:\t${JSON.stringify(tx3a)}\n`)
        await delay(30000)
        let tx3b = await strategy.harvest(GAS_CONFIG)
        write(`tx3b:\t${JSON.stringify(tx3b)}\n`)
        
        console.log('4. Panic the vault.');
        write('4. Panic the vault.\n');
        let tx4 = await strategy.panic(GAS_CONFIG)
        write(`tx4:\t${JSON.stringify(tx4)}\n`)
        
        console.log('5. Withdraw 50% while panicked to make sure users can leave.');
        write('5. Withdraw 50% while panicked to make sure users can leave.\n');
        let halfLittleAmount = littleAmount.div(2)
        let tx5 = await vault.withdraw(halfLittleAmount, GAS_CONFIG);
        write(`tx5:\t${JSON.stringify(tx5)}\n`)
        
        console.log('6. Try to deposit, you should get an error, dont send it through just make sure it pops up.');
        write('6. Try to deposit, you should get an error, dont send it through just make sure it pops up.\n');
        let tx6
        try {
            await want.approve(vault.address, halfLittleAmount, GAS_CONFIG);
            tx6 = await vault.deposit(halfLittleAmount, GAS_CONFIG);
        } catch (error) {
            console.log('\t We got and error, thats good my boy');
            write(`tx6:\t${JSON.stringify(tx6)}\n`)
            console.log(error);
        }
        
        console.log('7. Unpause the vault.');
        write('7. Unpause the vault.\n');
        let tx7 = await strategy.unpause(GAS_CONFIG)
        write(`tx7:\t${JSON.stringify(tx7)}\n`)
        
        console.log('8. Deposit the 50% you withdrew and harvest again.');
        write('8. Deposit the 50% you withdrew and harvest again.\n');
        await want.approve(vault.address, halfLittleAmount, GAS_CONFIG);
        let tx8 = await vault.deposit(halfLittleAmount, GAS_CONFIG);
        write(`tx8:\t${JSON.stringify(tx8)}\n`)
        
        console.log('9. Transfer ownership to multisig (on bsc).');
        write('9. Transfer ownership to multisig (on bsc).\n');
        console.log('\tSetting Beefy Keeper => ', addressBook[CHAIN_NAME].platforms.beefyfinance.keeper);
        if (ethers.utils.isAddress(addressBook[CHAIN_NAME].platforms.beefyfinance.keeper)) {
            let tx9a = await strategy.setKeeper(addressBook[CHAIN_NAME].platforms.beefyfinance.keeper, GAS_CONFIG)
            write(`tx9a (beefy keeper set):\t${JSON.stringify(tx9a)}\n`)
        }
        console.log('\tTransfering Strategy ownership to => ', addressBook[CHAIN_NAME].platforms.beefyfinance.strategyOwner)
        if (ethers.utils.isAddress(addressBook[CHAIN_NAME].platforms.beefyfinance.strategyOwner)){
            let tx9b = await strategy.transferOwnership(addressBook[CHAIN_NAME].platforms.beefyfinance.strategyOwner, GAS_CONFIG)
            write(`tx9b (strategy ownership transfered):\t${JSON.stringify(tx9b)}\n`)
        }
        console.log('\tTransfering Vault ownership to => ', addressBook[CHAIN_NAME].platforms.beefyfinance.vaultOwner)
        if (ethers.utils.isAddress(addressBook[CHAIN_NAME].platforms.beefyfinance.vaultOwner)){
            let tx9c = await vault.transferOwnership(addressBook[CHAIN_NAME].platforms.beefyfinance.vaultOwner, GAS_CONFIG)
            write(`tx9c (vault ownership transfered):\t${JSON.stringify(tx9c)}\n`)
        }

    } catch (error) {
        console.log({
            error
        });
    }

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });