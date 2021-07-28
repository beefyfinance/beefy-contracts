/*
* generate a pool.json with all Lp existed
* - adding a 'stats' prop en every lp object
* with states: { EXPIRED DEPLOYED AVAILABLE }
* so EXPIRED is when lp does not has rewards token anymore,
* DEPLOYED is when is already there is an vault with that LP
* and AVAILABLE is that is 'available to deploy' vault with
* this LP
*/