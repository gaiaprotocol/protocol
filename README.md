# Gaia Protocol

## Base Mainnet

Deploy
```sh
forge clean && forge script script/DeployPersonaFragments.s.sol \
  --rpc-url https://mainnet.base.org \
  --ledger \
  --sender 0x48674148a4043EAadB92E5D8D7C493121D6489b1 \
  --broadcast \
  --ffi \
  --verify \
  -vv
```

Upgrade
```sh
forge clean && forge script script/UpgradePersonaFragments.s.sol \
  --rpc-url https://mainnet.base.org \
  --ledger \
  --sender 0x48674148a4043EAadB92E5D8D7C493121D6489b1 \
  --broadcast \
  --ffi \
  --verify \
  -vv
```

```sh
##### base
✅  [Success] Hash: 0xcd7dd196d58be8977be092f49635c343143bbea05ac99adba684bf84da15eef3
Contract Address: 0x04A77bA08018B9b12429E6B49F687315Fc1D99cF
Block: 39187843
Paid: 0.000000607230342261 ETH (2954619 gas * 0.000205519 gwei)


##### base
✅  [Success] Hash: 0x803804bf35805b7459ce4617bfcf5f8f1d961ae2ac399c844b1a6657b0e164f9
Contract Address: 0x29C1A5cCE947560f10df4d9aA3B8Ee11ddA98a1A
Block: 39187845
Paid: 0.00000007414303444 ETH (360760 gas * 0.000205519 gwei)

✅ Sequence #1 on base | Total Paid: 0.000000681373376701 ETH (3315379 gas * avg 0.000205519 gwei)
```

- PersonaFragments: https://basescan.org/address/0x04a77ba08018b9b12429e6b49f687315fc1d99cf
- ERC1967Proxy: https://basescan.org/address/0x29c1a5cce947560f10df4d9aa3b8ee11dda98a1a

## Base Sepoila

Deploy
```sh
forge clean && forge script script/DeployPersonaFragments.s.sol \
  --rpc-url https://sepolia.base.org \
  --ledger \
  --sender 0x48674148a4043EAadB92E5D8D7C493121D6489b1 \
  --broadcast \
  --ffi \
  --verify \
  -vv
```

Upgrade
```sh
forge clean && forge script script/UpgradePersonaFragments.s.sol \
  --rpc-url https://sepolia.base.org \
  --ledger \
  --sender 0x48674148a4043EAadB92E5D8D7C493121D6489b1 \
  --broadcast \
  --ffi \
  --verify \
  -vv
```

```sh
##### base-sepolia
✅  [Success] Hash: 0xc5a3b0fd40fadc9291c13d9fd0b2faaa1b61f7f7f16c63c217fa34916c9909b4
Contract Address: 0xE59782E0c56ca3B5d8e6BBed0F6B8807978c7D0D
Block: 34698303
Paid: 0.0000035455428 ETH (2954619 gas * 0.0012 gwei)


##### base-sepolia
✅  [Success] Hash: 0x148bc1968ffdf73be9dc0d3594f5941222a2364caba863d0fc0f64c63a685eab
Contract Address: 0x140AEc1F9fd26B8eB2832aF5C449f3D0C2EA0836
Block: 34698305
Paid: 0.000000432912 ETH (360760 gas * 0.0012 gwei)

✅ Sequence #1 on base-sepolia | Total Paid: 0.0000039784548 ETH (3315379 gas * avg 0.0012 gwei)
```

- PersonaFragments: https://sepolia.basescan.org/address/0xe59782e0c56ca3b5d8e6bbed0f6b8807978c7d0d
- ERC1967Proxy: https://sepolia.basescan.org/address/0x140aec1f9fd26b8eb2832af5c449f3d0c2ea0836

## License

MIT OR Apache-2.0
