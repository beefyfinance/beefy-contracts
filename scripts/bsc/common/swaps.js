const { addressBook } = require("blockchain-addressbook");

let swaps = [
    {
        chain: 'bsc',
        name: 'PancakeSwap',
        prefix: 'CakeV2',
        beefyApiLp:'cake',
        url: 'exchange.pancakeswap.finance/#/',
        chef: addressBook.bsc.platforms.pancake.masterchef,
        router: addressBook.bsc.platforms.pancake.router,
        tokens: {
            reward: addressBook.bsc.tokens.CAKE,
            wnative: addressBook.bsc.tokens.WBNB
        }
    },
    {
        chain: 'bsc',
        name: 'AutoFarm',
        prefix: 'auto',
        beefyApiLp:'auto',
        url: 'exchange.pancakeswap.finance/#/',
        chef: addressBook.bsc.platforms.pancake.masterchef,
        router: addressBook.bsc.platforms.pancake.router,
        tokens: {
            reward: addressBook.bsc.tokens.CAKE,
            wnative: addressBook.bsc.tokens.WBNB
        }
    },
    {
        chain: 'bsc',
        name: 'ApeSwap',
        prefix: 'Ape',
        beefyApiLp:'ape',
        url: 'dex.apeswap.finance/#/',
        chef: addressBook.bsc.platforms.ape.masterape,
        router: addressBook.bsc.platforms.ape.router,
        tokens: {
            reward: addressBook.bsc.tokens.BANANA,
            wnative: addressBook.bsc.tokens.WNATIVE
        }
    },
    {
        chain: 'bsc',
        name: 'Bakery',
        prefix: 'Bakery',
        beefyApiLp:'bakery',
        url: 'bakeryswap.org/#/',
        chef: addressBook.bsc.platforms.ape.masterape,
        router: addressBook.bsc.platforms.ape.router,
        tokens: {
            reward: addressBook.bsc.tokens.BANANA,
            wnative: addressBook.bsc.tokens.WNATIVE
        }
    },
    {
        chain: 'bsc',
        name: 'Kebab',
        prefix: 'kebab',
        beefyApiLp:'kebab',
        url: 'swap.kebabfinance.com/#/',
        chef: addressBook.bsc.platforms.ape.masterape,
        router: addressBook.bsc.platforms.ape.router,
        tokens: {
            reward: addressBook.bsc.tokens.BANANA,
            wnative: addressBook.bsc.tokens.WNATIVE
        }
    },
    {
        chain: 'bsc',
        name: 'JetSwap',
        prefix: 'jetswap',
        beefyApiLp:'jetswap',
        url: 'exchange.jetswap.finance/#/',
        chef: addressBook.bsc.platforms.ape.masterape,
        router: addressBook.bsc.platforms.ape.router,
        tokens: {
            reward: addressBook.bsc.tokens.BANANA,
            wnative: addressBook.bsc.tokens.WNATIVE
        }
    },
    {
        chain: 'bsc',
        name: 'mdex',
        prefix: 'mdex-bsc',
        beefyApiLp:'mdexBsc',
        url: 'exchange.pancakeswap.finance/#/',
        chef: addressBook.bsc.platforms.ape.masterape,
        router: addressBook.bsc.platforms.ape.router,
        tokens: {
            reward: addressBook.bsc.tokens.BANANA,
            wnative: addressBook.bsc.tokens.WNATIVE
        }
    },
    {
        chain: 'bsc',
        name: 'Wault',
        prefix: 'wex',
        beefyApiLp:'wault',
        url: 'swap.wault.finance/bsc/index.html#',
        chef: addressBook.bsc.platforms.ape.masterape,
        router: addressBook.bsc.platforms.ape.router,
        tokens: {
            reward: addressBook.bsc.tokens.BANANA,
            wnative: addressBook.bsc.tokens.WNATIVE
        }
    },

]

module.exports = swaps