// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GaiaProtocolTokenTestnet is ERC20 {
    // ------------------------------------------------------------------
    // Constants & Custom Errors
    // ------------------------------------------------------------------
    uint8 private constant DECIMALS = 18;
    uint256 private constant MAX_MINT = 10_000 * 10 ** DECIMALS;

    error MaxMintExceeded();

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------
    constructor() ERC20("Gaia Protocol", "GAIA") {}

    // ------------------------------------------------------------------
    // Test‑net mint function (no access control)
    // ------------------------------------------------------------------
    function mintForTest(uint256 amount) external {
        if (amount > MAX_MINT) revert MaxMintExceeded();
        _mint(msg.sender, amount);
    }
}
