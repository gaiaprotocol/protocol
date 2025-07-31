// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract GaiaProtocolToken is ERC20Permit {
    constructor() ERC20("Gaia Protocol", "GAIA") ERC20Permit("Gaia Protocol") {
        _mint(msg.sender, 100_000_000 * 10 ** decimals());
    }
}
