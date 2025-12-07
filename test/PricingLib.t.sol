// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/libraries/PricingLib.sol";

contract PricingLibTest is Test {
    uint256 constant PRICE_INCREMENT = 1e15; // 0.001 ETH
    uint256 constant UNITS_18 = 1e18; // ERC20 18 decimals
    uint256 constant UNITS_1 = 1; // integer units (e.g. persona)

    /// -----------------------------------------------------------------------
    /// String / Formatting Helpers
    /// -----------------------------------------------------------------------

    /// @notice Basic uint256 → decimal string conversion
    function _uToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;

        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /// @notice Left pads a numeric string with zeros to a fixed length
    function _padLeft(string memory str, uint256 length) internal pure returns (string memory) {
        bytes memory b = bytes(str);
        if (b.length >= length) return str;

        bytes memory padded = new bytes(length);
        uint256 diff = length - b.length;

        for (uint256 i = 0; i < diff; i++) {
            padded[i] = "0";
        }
        for (uint256 j = 0; j < b.length; j++) {
            padded[diff + j] = b[j];
        }
        return string(padded);
    }

    /// @notice Formats wei into "X.YYYYYYYY ETH" (8 decimals)
    function formatETH(uint256 weiAmount) internal pure returns (string memory) {
        uint256 integer = weiAmount / 1e18;
        uint256 decimals = (weiAmount % 1e18) / 1e10; // 1e18 / 1e8 = 1e10

        return string(abi.encodePacked(_uToString(integer), ".", _padLeft(_uToString(decimals), 8), " ETH"));
    }

    /// @notice Formats token amount using unitsPerToken into "X.YYYYYYYY tokens"
    ///         or integer "N tokens" when unitsPerToken == 1
    function formatTokenAmount(uint256 rawAmount, uint256 unitsPerToken) internal pure returns (string memory) {
        // Integer-based tokens (no decimals, e.g. persona fragments)
        if (unitsPerToken == 1) {
            return string(abi.encodePacked(_uToString(rawAmount), " tokens"));
        }

        uint256 integer = rawAmount / unitsPerToken;
        uint256 decimals = (rawAmount % unitsPerToken) / (unitsPerToken / 1e8); // 8 decimals

        return string(abi.encodePacked(_uToString(integer), ".", _padLeft(_uToString(decimals), 8), " tokens"));
    }

    /// -----------------------------------------------------------------------
    /// Tests
    /// -----------------------------------------------------------------------

    /// @notice supply=0, amount=1 whole token -> price = 0.001 ETH
    function testPrice_ZeroToOneWholeToken_18Decimals() public {
        uint256 supply = 0;
        uint256 amount = 1e18; // 1 token

        uint256 price = PricingLib.getPrice(supply, amount, PRICE_INCREMENT, UNITS_18);

        console.log("=== ZeroToOneWholeToken_18Decimals ===");
        console.log("Supply: ", formatTokenAmount(supply, UNITS_18));
        console.log("Amount: ", formatTokenAmount(amount, UNITS_18));
        console.log("Price:  ", formatETH(price));
        console.log("");

        assertEq(price, 1e15, "0 -> 1 token price should be 0.001 ETH");
    }

    /// @notice persona-style unit: supply=0, amount=1 -> price = 0.001 ETH
    function testPrice_ZeroToOnePersonaUnit() public {
        uint256 supply = 0;
        uint256 amount = 1; // 1 fragment

        uint256 price = PricingLib.getPrice(supply, amount, PRICE_INCREMENT, UNITS_1);

        console.log("=== ZeroToOnePersonaUnit ===");
        console.log("Supply: ", formatTokenAmount(supply, UNITS_1));
        console.log("Amount: ", formatTokenAmount(amount, UNITS_1));
        console.log("Price:  ", formatETH(price));
        console.log("");

        assertEq(price, 1e15, "0 -> 1 persona unit should be 0.001 ETH");
    }

    /// @notice Continuous curve matches discrete step-sum for integer units
    /// Example: supply=2, amount=3 -> prices = p*(3 + 4 + 5) = 12p
    function testPrice_MatchesDiscreteSum_IntegerUnits() public {
        uint256 p = PRICE_INCREMENT;
        uint256 S = 2;
        uint256 A = 3;

        uint256 price = PricingLib.getPrice(S, A, p, UNITS_1);

        uint256 expected = p * ((2 + 1) + (2 + 2) + (2 + 3)); // 3 + 4 + 5 = 12p

        console.log("=== MatchesDiscreteSum_IntegerUnits ===");
        console.log("Supply:    ", formatTokenAmount(S, UNITS_1));
        console.log("Amount:    ", formatTokenAmount(A, UNITS_1));
        console.log("Calculated:", formatETH(price));
        console.log("Expected:  ", formatETH(expected));
        console.log("");

        assertEq(price, expected, "Continuous price must match discrete sum");
    }

    /// @notice Same check but with ERC20 18-decimals representation
    function testPrice_MatchesDiscreteSum_18Decimals() public {
        uint256 p = PRICE_INCREMENT;

        uint256 supply = 2 * UNITS_18; // 2 tokens
        uint256 amount = 3 * UNITS_18; // 3 tokens

        uint256 price = PricingLib.getPrice(supply, amount, p, UNITS_18);

        uint256 expected = p * ((2 + 1) + (2 + 2) + (2 + 3)); // 3+4+5=12p

        console.log("=== MatchesDiscreteSum_18Decimals ===");
        console.log("Supply:    ", formatTokenAmount(supply, UNITS_18));
        console.log("Amount:    ", formatTokenAmount(amount, UNITS_18));
        console.log("Calculated:", formatETH(price));
        console.log("Expected:  ", formatETH(expected));
        console.log("");

        assertEq(price, expected, "Continuous price must match discrete sum (18 decimals)");
    }

    /// @notice If you buy amount A then sell A, the prices should match
    /// and we also log average per-token prices.
    function testBuyThenSellSameAmount_ReturnsSamePrice() public {
        uint256 supply = 5 * UNITS_18; // initial supply = 5 tokens
        uint256 amount = 2 * UNITS_18; // trade 2 tokens

        uint256 buyPrice = PricingLib.getBuyPrice(supply, amount, PRICE_INCREMENT, UNITS_18);
        uint256 sellPrice = PricingLib.getSellPrice(supply + amount, amount, PRICE_INCREMENT, UNITS_18);

        // number of whole tokens traded (not in wei)
        uint256 tokensTraded = amount / UNITS_18; // = 2
        uint256 avgBuyPerToken = buyPrice / tokensTraded;
        uint256 avgSellPerToken = sellPrice / tokensTraded;

        console.log("=== BuyThenSell Symmetry ===");
        console.log("Initial Supply:         ", formatTokenAmount(supply, UNITS_18));
        console.log("Trade Amount:           ", formatTokenAmount(amount, UNITS_18));
        console.log("Final Supply:           ", formatTokenAmount(supply + amount, UNITS_18));
        console.log("Total Buy Price:        ", formatETH(buyPrice));
        console.log("Total Sell Price:       ", formatETH(sellPrice));
        console.log("Avg Buy Price / token:  ", formatETH(avgBuyPerToken));
        console.log("Avg Sell Price / token: ", formatETH(avgSellPerToken));
        console.log("");

        assertEq(buyPrice, sellPrice, "Buying then selling same amount should match");
        assertEq(avgBuyPerToken, avgSellPerToken, "Average per-token prices must also match");
    }

    /// @notice Fractional purchase is sublinear: 2 * price(0.5) < price(1)
    function testPrice_FractionalAmountIsLessThanProportional() public {
        uint256 supply = 0;
        uint256 half = UNITS_18 / 2;
        uint256 one = UNITS_18;

        uint256 priceHalf = PricingLib.getPrice(supply, half, PRICE_INCREMENT, UNITS_18);
        uint256 priceOne = PricingLib.getPrice(supply, one, PRICE_INCREMENT, UNITS_18);

        console.log("=== FractionalAmount Convexity ===");
        console.log("Supply:          ", formatTokenAmount(supply, UNITS_18));
        console.log("Amount 0.5:      ", formatTokenAmount(half, UNITS_18));
        console.log("Price(0.5):      ", formatETH(priceHalf));
        console.log("Amount 1.0:      ", formatTokenAmount(one, UNITS_18));
        console.log("Price(1.0):      ", formatETH(priceOne));
        console.log("2 * Price(0.5):  ", formatETH(priceHalf * 2));
        console.log("");

        assertGt(priceHalf, 0, "0.5 price must be > 0");
        assertGt(priceOne, 0, "1.0 price must be > 0");
        assertLt(priceHalf * 2, priceOne, "Curve must be convex");
    }

    /// @notice Buy 0.5 token first, then buy another 0.5 token; second price must be higher.
    function testPrice_HalfThenHalfBuy() public {
        uint256 S0 = 0;
        uint256 half = UNITS_18 / 2;

        // First purchase: supply 0 → 0.5
        uint256 priceFirst = PricingLib.getPrice(S0, half, PRICE_INCREMENT, UNITS_18);

        // New supply after first purchase
        uint256 S1 = S0 + half; // 0.5 tokens

        // Second purchase: supply 0.5 → 1.0
        uint256 priceSecond = PricingLib.getPrice(S1, half, PRICE_INCREMENT, UNITS_18);

        console.log("=== HalfThenHalf Buy Test ===");
        console.log("Initial Supply:    ", formatTokenAmount(S0, UNITS_18));
        console.log("First Buy Amount:  ", formatTokenAmount(half, UNITS_18));
        console.log("First Price:       ", formatETH(priceFirst));
        console.log("Supply After Buy:  ", formatTokenAmount(S1, UNITS_18));
        console.log("Second Buy Amount: ", formatTokenAmount(half, UNITS_18));
        console.log("Second Price:      ", formatETH(priceSecond));
        console.log("");

        assertGt(priceFirst, 0, "first 0.5 token price must be > 0");
        assertGt(priceSecond, priceFirst, "second 0.5 token price must be higher due to increased supply");
    }

    /// @notice Very large supply and large trade amount should not overflow and must return a positive price.
    function testPrice_LargeSupplyAndLargeAmount() public {
        uint256 supplyTokens = 1_000_000_000; // 1 billion tokens
        uint256 amountTokens = 1_000_000; // 1 million tokens

        uint256 supply = supplyTokens * UNITS_18;
        uint256 amount = amountTokens * UNITS_18;

        uint256 price = PricingLib.getPrice(supply, amount, PRICE_INCREMENT, UNITS_18);

        console.log("=== LargeSupplyAndLargeAmount ===");
        console.log("Supply (tokens): ", formatTokenAmount(supply, UNITS_18));
        console.log("Amount (tokens): ", formatTokenAmount(amount, UNITS_18));
        console.log("Price:           ", formatETH(price));
        console.log("");

        assertGt(price, 0, "price must be > 0 for large supply/amount");
    }

    /// @notice Buy and then sell the same large amount at large supply;
    /// total buy and sell price must match (pure curve, no fees).
    function testBuyThenSell_LargeNumbers_Symmetric() public {
        uint256 initialSupplyTokens = 1_000_000_000; // 1 billion tokens
        uint256 tradeTokens = 1_000_000; // 1 million tokens

        uint256 supply = initialSupplyTokens * UNITS_18;
        uint256 amount = tradeTokens * UNITS_18;

        uint256 buyPrice = PricingLib.getBuyPrice(supply, amount, PRICE_INCREMENT, UNITS_18);
        uint256 sellPrice = PricingLib.getSellPrice(supply + amount, amount, PRICE_INCREMENT, UNITS_18);

        uint256 avgBuyPerToken = buyPrice / tradeTokens;
        uint256 avgSellPerToken = sellPrice / tradeTokens;

        console.log("=== BuyThenSell LargeNumbers Symmetry ===");
        console.log("Initial Supply:          ", formatTokenAmount(supply, UNITS_18));
        console.log("Trade Amount:            ", formatTokenAmount(amount, UNITS_18));
        console.log("Final Supply:            ", formatTokenAmount(supply + amount, UNITS_18));
        console.log("Total Buy Price:         ", formatETH(buyPrice));
        console.log("Total Sell Price:        ", formatETH(sellPrice));
        console.log("Avg Buy Price / token:   ", formatETH(avgBuyPerToken));
        console.log("Avg Sell Price / token:  ", formatETH(avgSellPerToken));
        console.log("");

        assertGt(buyPrice, 0, "buy price must be > 0");
        assertEq(buyPrice, sellPrice, "total buy and total sell must match at large scale");
        assertEq(avgBuyPerToken, avgSellPerToken, "avg buy/sell per token must match at large scale");
    }
}
