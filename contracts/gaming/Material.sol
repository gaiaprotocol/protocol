// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract Material is ERC20Permit, Ownable2Step {
    address public immutable factory;

    string private _name;
    string private _symbol;

    mapping(address => bool) public whitelist;

    event NameUpdated(string name);
    event SymbolUpdated(string symbol);
    event WhitelistAdded(address indexed account);
    event WhitelistRemoved(address indexed account);
    event Deleted();

    constructor(
        address owner_,
        string memory name_,
        string memory symbol_
    ) ERC20Permit("Material") ERC20("", "") Ownable(owner_) {
        factory = msg.sender;
        _name = name_;
        _symbol = symbol_;

        emit NameUpdated(name_);
        emit SymbolUpdated(symbol_);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function updateName(string memory name_) external onlyOwner {
        _name = name_;
        emit NameUpdated(name_);
    }

    function updateSymbol(string memory symbol_) external onlyOwner {
        _symbol = symbol_;
        emit SymbolUpdated(symbol_);
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "Material: caller is not the factory");
        _;
    }

    function mint(address to, uint256 amount) external onlyFactory {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyFactory {
        _burn(from, amount);
    }

    function deleteMaterial() external onlyFactory {
        _name = "";
        _symbol = "";
        renounceOwnership();
        emit Deleted();
    }

    function addToWhitelist(address[] calldata _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            require(!whitelist[_addresses[i]], "Address is already whitelisted");
            whitelist[_addresses[i]] = true;
            emit WhitelistAdded(_addresses[i]);
        }
    }

    function removeFromWhitelist(address[] calldata _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            require(whitelist[_addresses[i]], "Address is not whitelisted");
            whitelist[_addresses[i]] = false;
            emit WhitelistRemoved(_addresses[i]);
        }
    }

    function isWhitelisted(address _address) public view returns (bool) {
        return whitelist[_address];
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        if (whitelist[msg.sender]) {
            _transfer(sender, recipient, amount);
            return true;
        }
        return super.transferFrom(sender, recipient, amount);
    }
}
