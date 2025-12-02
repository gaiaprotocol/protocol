// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20Permit, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract Material is ERC20Permit, Ownable2Step {
    // ---------------------------------------------------------------------
    // Custom Errors (gas‑efficient replacements for require statements)
    // ---------------------------------------------------------------------
    error CallerNotFactory();
    error AlreadyWhitelisted();
    error NotWhitelisted();

    // ---------------------------------------------------------------------
    // Immutable state
    // ---------------------------------------------------------------------
    address public immutable FACTORY;

    // ---------------------------------------------------------------------
    // Token metadata (mutable to allow post‑deployment branding)
    // ---------------------------------------------------------------------
    string private _name;
    string private _symbol;

    // ---------------------------------------------------------------------
    // Whitelist mapping
    // ---------------------------------------------------------------------
    mapping(address => bool) public whitelist;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    event NameUpdated(string name);
    event SymbolUpdated(string symbol);
    event WhitelistAdded(address indexed account);
    event WhitelistRemoved(address indexed account);
    event Deleted();

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------
    constructor(address owner_, string memory name_, string memory symbol_)
        ERC20Permit("Material")
        ERC20("", "")
        Ownable(owner_)
    {
        FACTORY = msg.sender;
        _name = name_;
        _symbol = symbol_;

        emit NameUpdated(name_);
        emit SymbolUpdated(symbol_);
    }

    // ---------------------------------------------------------------------
    // Metadata getters
    // ---------------------------------------------------------------------
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    // ---------------------------------------------------------------------
    // Metadata setters
    // ---------------------------------------------------------------------
    function updateName(string memory name_) external onlyOwner {
        _name = name_;
        emit NameUpdated(name_);
    }

    function updateSymbol(string memory symbol_) external onlyOwner {
        _symbol = symbol_;
        emit SymbolUpdated(symbol_);
    }

    // ---------------------------------------------------------------------
    // Access control
    // ---------------------------------------------------------------------
    modifier onlyFactory() {
        if (msg.sender != FACTORY) revert CallerNotFactory();
        _;
    }

    // ---------------------------------------------------------------------
    // Mint / Burn controlled by factory
    // ---------------------------------------------------------------------
    function mint(address to, uint256 amount) external onlyFactory {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyFactory {
        _burn(from, amount);
    }

    // ---------------------------------------------------------------------
    // "Delete" token (irreversible)
    // ---------------------------------------------------------------------
    function deleteMaterial() external onlyFactory {
        _name = "";
        _symbol = "";
        renounceOwnership();
        emit Deleted();
    }

    // ---------------------------------------------------------------------
    // Whitelist management
    // ---------------------------------------------------------------------
    function addToWhitelist(address[] calldata _addresses) external onlyOwner {
        uint256 len = _addresses.length;
        for (uint256 i = 0; i < len; ++i) {
            address addr = _addresses[i];
            if (whitelist[addr]) revert AlreadyWhitelisted();
            whitelist[addr] = true;
            emit WhitelistAdded(addr);
        }
    }

    function removeFromWhitelist(address[] calldata _addresses) external onlyOwner {
        uint256 len = _addresses.length;
        for (uint256 i = 0; i < len; ++i) {
            address addr = _addresses[i];
            if (!whitelist[addr]) revert NotWhitelisted();
            whitelist[addr] = false;
            emit WhitelistRemoved(addr);
        }
    }

    function isWhitelisted(address _address) public view returns (bool) {
        return whitelist[_address];
    }

    // ---------------------------------------------------------------------
    // ERC20 override with whitelist bypass
    // ---------------------------------------------------------------------
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        if (whitelist[msg.sender]) {
            _transfer(sender, recipient, amount);
            return true;
        }
        return super.transferFrom(sender, recipient, amount);
    }
}
