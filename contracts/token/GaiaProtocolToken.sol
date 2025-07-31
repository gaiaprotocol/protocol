// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20Permit, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract GaiaProtocolToken is ERC20Permit {
    // Initial supply: 100 000 000 tokens, 18 decimals
    uint256 private constant INITIAL_SUPPLY = 100_000_000 * 10 ** 18;

    constructor() ERC20("Gaia Protocol", "GAIA") ERC20Permit("Gaia Protocol") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
