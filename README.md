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
  --verify
```

```sh
##### base-sepolia
✅  [Success] Hash: 0x187a24b7aafa43bfde60f08b422e758addcd5ee01fc905a9539d219506d3a92d
Contract Address: 0x2B4d62D12d7D1857d9f6780C5673C316A8A57673
Block: 34143501
Paid: 0.0000035227296 ETH (2935608 gas * 0.0012 gwei)


##### base-sepolia
✅  [Success] Hash: 0x73756ed3c4998106b9ed86f26668f33dcc33052b892bdd1e9d6adc28397a3298
Contract Address: 0x4A5F1a26a51dE4aD334B5d6F598522455bF5bf86
Block: 34143502
Paid: 0.0000004328832 ETH (360736 gas * 0.0012 gwei)

✅ Sequence #1 on base-sepolia | Total Paid: 0.0000039556128 ETH (3296344 gas * avg 0.0012 gwei)
```

- PersonaFragments: https://sepolia.basescan.org/address/0x2b4d62d12d7d1857d9f6780c5673c316a8a57673
- ERC1967Proxy: https://sepolia.basescan.org/address/0x4a5f1a26a51de4ad334b5d6f598522455bf5bf86

## License

MIT OR Apache-2.0
