# Questions:
*	Can storage variables be used specifically for off-chain use in an eth_call?
Use case: storing a gasPrice in storage to be only used locally, to use as “global variable” for the lifetime of the checkUpkeep call
*	Are off chain simulations subject to the block gas limit? This will decide whether we can perform a harvest in the checker function or not.
*	How to encode and send multiple variables to the performUpkeep function. In our case, new startIndex + list of vaults to harvest
*	Gas price is in signed int, need to make sure conversion is correct
*	Units of gas price from oracle? Wei or gwei?
*   Can we have a gas oracle per chain?
*   What gasprice will keepers use? Can we increase this to not get frontrun? Stretch question: will there be flashbot integration ever?
*	Will gas price be similar across check and perform calls? If yes doesn’t that mean we can maybe use tx.gasprice (unless this isn’t accessible or set during an eth_call), rather than oracle?
*	Will block.gaslimit be the same off as onchain 

* reliablility


# Notes:

* gasPrice will be used as function param. tx.gasprice
* v2 will have service level config for gas price
* 2.5 mil gas limit
* on bsc and poly, there would be flat link fee per tx.
* if we use whole block limit, can take a while for it to confirm. Will have to play around with gas limit and confirmation time.
* look at multiple upkeeps.