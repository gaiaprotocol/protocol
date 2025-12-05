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
✅  [Success] Hash: 0x7aeff7a4c9af6c7c443379626d1385b7bb6a77cee9890a11c87d5052b6cc4d26
Contract Address: 0x20b81Afb99CF3A279c7baf4cB54e2fC2b8be4963
Block: 34447486
Paid: 0.000005099398114896 ETH (2950303 gas * 0.001728432 gwei)


##### base-sepolia
✅  [Success] Hash: 0xdcb08b5a0df932ea4f9c7f085ae8b89c9860e1924c6dc81d0ebfc77556b701ed
Contract Address: 0x4720B04934c87388a7b9413413E2378EFF1D117C
Block: 34447488
Paid: 0.000000621966942496 ETH (360736 gas * 0.001724161 gwei)

✅ Sequence #1 on base-sepolia | Total Paid: 0.000005721365057392 ETH (3311039 gas * avg 0.001726296 gwei)
```

- PersonaFragments: https://sepolia.basescan.org/address/0x20b81afb99cf3a279c7baf4cb54e2fc2b8be4963
- ERC1967Proxy: https://sepolia.basescan.org/address/0x4720b04934c87388a7b9413413e2378eff1d117c

## License

MIT OR Apache-2.0
