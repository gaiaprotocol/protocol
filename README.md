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
✅  [Success] Hash: 0x2c9e329fc36442b6118a45660a876e52793878ab14305447afef1ed33caad7d4
Contract Address: 0x1BBadA20026b30a4527a5aFdC8bAbdc3e00aB5F0
Block: 39617752
Paid: 0.00000141325601516 ETH (360760 gas * 0.003917441 gwei)


##### base
✅  [Success] Hash: 0x01178f27f368caa4777ca19af7367cb04f2a38393b80c483a8a45707e64d1688
Contract Address: 0x936F400412bD9104578BD44ec2d9bB158e34450E
Block: 39617750
Paid: 0.000011631999140748 ETH (2958053 gas * 0.003932316 gwei)

✅ Sequence #1 on base | Total Paid: 0.000013045255155908 ETH (3318813 gas * avg 0.003924878 gwei)
```

- PersonaFragments: https://basescan.org/address/0x936f400412bd9104578bd44ec2d9bb158e34450e
- ERC1967Proxy: https://basescan.org/address/0x1bbada20026b30a4527a5afdc8babdc3e00ab5f0

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
✅  [Success] Hash: 0xc0fbdeb0bf13a6bf105938314d7fe5871c7ce4f8aab70bcad1ed33e9dbba0f26
Contract Address: 0x11C8631840D0A76836cbfe8e0bf0452525f83aD9
Block: 35128233
Paid: 0.0000035496636 ETH (2958053 gas * 0.0012 gwei)


##### base-sepolia
✅  [Success] Hash: 0x1ce75a02420bfd1bd37f6ada09206c6772d941decd5233ab970c29ffe760cd33
Contract Address: 0xdAd0dEE876BddB30558882E54B563f88ADde30e0
Block: 35128235
Paid: 0.000000432912 ETH (360760 gas * 0.0012 gwei)

✅ Sequence #1 on base-sepolia | Total Paid: 0.0000039825756 ETH (3318813 gas * avg 0.0012 gwei)
```

- PersonaFragments: https://sepolia.basescan.org/address/0x11c8631840d0a76836cbfe8e0bf0452525f83ad9
- ERC1967Proxy: https://sepolia.basescan.org/address/0xdad0dee876bddb30558882e54b563f88adde30e0

## License

MIT OR Apache-2.0
