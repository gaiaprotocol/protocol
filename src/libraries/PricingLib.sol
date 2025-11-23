// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library PricingLib {
    function getPrice(
        uint256 supply,
        uint256 amount,
        uint256 priceIncrement,
        uint256 scaleFactor
    ) internal pure returns (uint256) {
        uint256 startPrice = priceIncrement + (supply * priceIncrement) / scaleFactor;
        uint256 endSupply = supply + amount;
        uint256 endPrice = priceIncrement + (endSupply * priceIncrement) / scaleFactor;

        uint256 averagePrice = (startPrice + endPrice) / 2;
        return (averagePrice * amount) / scaleFactor;
    }

    function getBuyPrice(
        uint256 supply,
        uint256 amount,
        uint256 priceIncrement,
        uint256 scaleFactor
    ) internal pure returns (uint256) {
        return getPrice(supply, amount, priceIncrement, scaleFactor);
    }

    function getSellPrice(
        uint256 supply,
        uint256 amount,
        uint256 priceIncrement,
        uint256 scaleFactor
    ) internal pure returns (uint256) {
        uint256 supplyAfterSale = supply - amount;
        return getPrice(supplyAfterSale, amount, priceIncrement, scaleFactor);
    }
}
