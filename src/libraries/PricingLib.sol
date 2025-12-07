// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library PricingLib {
    function getPrice(uint256 supply, uint256 amount, uint256 priceIncrement, uint256 unitsPerToken)
        internal
        pure
        returns (uint256)
    {
        uint256 S = supply;
        uint256 A = amount;
        uint256 U = unitsPerToken;

        uint256 SplusA = S + A;
        uint256 sqDiff = SplusA * SplusA - S * S;

        uint256 term1 = (priceIncrement * sqDiff) / (2 * U * U);
        uint256 term2 = (priceIncrement * A) / (2 * U);

        return term1 + term2;
    }

    function getBuyPrice(uint256 supply, uint256 amount, uint256 priceIncrement, uint256 unitsPerToken)
        internal
        pure
        returns (uint256)
    {
        return getPrice(supply, amount, priceIncrement, unitsPerToken);
    }

    function getSellPrice(uint256 supply, uint256 amount, uint256 priceIncrement, uint256 unitsPerToken)
        internal
        pure
        returns (uint256)
    {
        uint256 supplyAfterSale = supply - amount;
        return getPrice(supplyAfterSale, amount, priceIncrement, unitsPerToken);
    }
}
