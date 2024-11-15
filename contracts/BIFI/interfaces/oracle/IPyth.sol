// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPyth {
     struct Price {
        // Price
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp describing when the price was published
        uint publishTime;
    }

    function getPriceUnsafe(bytes32 priceId) 
        external 
        view 
        returns (Price memory price);
}