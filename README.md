# Gaia Protocol

## Base Mainnet

## Base Sepoila

Deploy
```sh
forge script script/DeployPersonaFragments.s.sol \
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
forge script script/UpgradePersonaFragments.s.sol \
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
✅  [Success] Hash: 0xb056bb4297e389d53bdb6350a39e816368249c4e7dde72d50789ca1328ae87c3
Contract Address: 0x5dB776C722Bc38eBD2a7354a7B51dD734C09D9fA
Block: 34185807
Paid: 0.0000004328832 ETH (360736 gas * 0.0012 gwei)


##### base-sepolia
✅  [Success] Hash: 0x8f3360614ae8a4b70e898929bd293687d87fb03c7f81dc2229801dafc2979724
Contract Address: 0x21Be75C9062D2Cba12EaBBdf92d47C4409827c0D
Block: 34185805
Paid: 0.0000035227296 ETH (2935608 gas * 0.0012 gwei)

✅ Sequence #1 on base-sepolia | Total Paid: 0.0000039556128 ETH (3296344 gas * avg 0.0012 gwei)
```

- PersonaFragments: https://sepolia.basescan.org/address/0x21be75c9062d2cba12eabbdf92d47c4409827c0d
- ERC1967Proxy: https://sepolia.basescan.org/address/0x5db776c722bc38ebd2a7354a7b51dd734c09d9fa

## License

MIT OR Apache-2.0
