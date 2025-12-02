// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

// UUPS proxy
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Contracts under test
import {PersonaFragments} from "../src/social/PersonaFragments.sol";
import {HoldingRewardsBase} from "../src/social/HoldingRewardsBase.sol";

// Signature utilities (used the same way as inside the contract)
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract PersonaFragmentsTest is Test {
    using MessageHashUtils for bytes32;

    PersonaFragments internal persona;

    // Config parameters for initialization
    address payable internal protocolFeeRecipient = payable(address(0xA11CE));
    uint256 internal protocolFeeRate = 0.1 ether; // 10%
    uint256 internal personaOwnerFeeRate = 0.05 ether; // 5%
    uint256 internal priceIncrementPerFragment = 1e15; // sample value

    // Private key used to sign reward authorization
    uint256 internal verifierPk;
    address internal holdingVerifier;

    // Test users
    address internal trader = address(0xB0B);
    address internal personaAddr = address(0xCAFE);

    function setUp() public {
        // Assign the reward verifier key
        verifierPk = 0xA11CE;
        holdingVerifier = vm.addr(verifierPk);

        // Deploy implementation contract
        PersonaFragments impl = new PersonaFragments();

        // Encode initializer call
        bytes memory initData = abi.encodeWithSelector(
            PersonaFragments.initialize.selector,
            protocolFeeRecipient,
            protocolFeeRate,
            personaOwnerFeeRate,
            priceIncrementPerFragment,
            holdingVerifier
        );

        // Deploy proxy + initialize
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Cast the proxy to the PersonaFragments interface
        persona = PersonaFragments(address(proxy));

        // Fund test accounts
        vm.deal(trader, 1000 ether);
        vm.deal(personaAddr, 0); // persona fee recipient initially has 0
    }

    // ---------------------------------------------------------
    // Helper: Generate a valid signature for holding rewards
    // ---------------------------------------------------------
    function _signReward(address contractAddr, address user, uint256 rewardRatio, uint256 nonce)
        internal
        view
        returns (bytes memory sig)
    {
        // Must match HoldingRewardsBase's internal hashing logic
        bytes32 hash = keccak256(abi.encodePacked(contractAddr, block.chainid, user, rewardRatio, nonce));
        bytes32 ethSigned = hash.toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifierPk, ethSigned);
        sig = abi.encodePacked(r, s, v);
    }

    // ---------------------------------------------------------
    // 1. Validate initialization state
    // ---------------------------------------------------------
    function testInitializeState() public view {
        assertEq(persona.protocolFeeRecipient(), protocolFeeRecipient);
        assertEq(persona.protocolFeeRate(), protocolFeeRate);
        assertEq(persona.personaOwnerFeeRate(), personaOwnerFeeRate);
        assertEq(persona.priceIncrementPerFragment(), priceIncrementPerFragment);
        assertEq(persona.holdingVerifier(), holdingVerifier);

        // OwnableUpgradeable v5 behavior: owner should be this test contract
        assertEq(persona.owner(), address(this));
    }

    // ---------------------------------------------------------
    // 2. Buying without a signature should produce no reward
    // ---------------------------------------------------------
    function testBuyWithoutSignature_NoReward_NoNonceIncrement() public {
        uint256 amount = 10;

        vm.prank(trader);
        uint256 price = persona.getBuyPrice(personaAddr, amount);

        uint256 rawProtocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 personaFee = (price * personaOwnerFeeRate) / 1 ether;
        uint256 totalCost = price + rawProtocolFee + personaFee;

        uint256 beforeTrader = trader.balance;
        uint256 beforeProtocol = protocolFeeRecipient.balance;
        uint256 beforePersona = personaAddr.balance;

        vm.prank(trader);
        persona.buy{value: totalCost}(
            personaAddr,
            amount,
            0, // no reward ratio (ignored)
            0, // nonce ignored
            "" // empty signature => reward skipped
        );

        // Balances should reflect the trade
        assertEq(persona.balance(personaAddr, trader), amount);
        assertEq(persona.supply(personaAddr), amount);

        // Protocol and persona fees must be paid
        assertEq(protocolFeeRecipient.balance, beforeProtocol + rawProtocolFee);
        assertEq(personaAddr.balance, beforePersona + personaFee);

        // Trader pays exactly the total cost (ignoring gas)
        assertEq(beforeTrader - trader.balance, totalCost);

        // Nonce must not increment if signature is empty
        assertEq(persona.nonces(trader), 0);
    }

    // ---------------------------------------------------------
    // 3. Buying with a valid reward signature should:
    //    - distribute reward correctly
    //    - increment nonce
    // ---------------------------------------------------------
    function testBuyWithHoldingReward_IncrementsNonce_UpdatesFees() public {
        uint256 amount = 5;
        uint256 rewardRatio = 0.2 ether; // 20%

        // Expect current nonce to be zero
        assertEq(persona.nonces(trader), 0);

        uint256 price = persona.getBuyPrice(personaAddr, amount);
        uint256 rawProtocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 personaBaseFee = (price * personaOwnerFeeRate) / 1 ether;

        uint256 nonce = 0;
        bytes memory sig = _signReward(address(persona), trader, rewardRatio, nonce);

        uint256 holdingReward = (rawProtocolFee * rewardRatio) / 1 ether;
        uint256 protocolFee = rawProtocolFee - holdingReward;
        uint256 personaFee = personaBaseFee + holdingReward;
        uint256 totalCost = price + protocolFee + personaFee;

        uint256 beforeProtocol = protocolFeeRecipient.balance;
        uint256 beforePersona = personaAddr.balance;

        vm.prank(trader);
        persona.buy{value: totalCost}(personaAddr, amount, rewardRatio, nonce, sig);

        // Fees should reflect reward shifting from protocol to persona
        assertEq(protocolFeeRecipient.balance, beforeProtocol + protocolFee);
        assertEq(personaAddr.balance, beforePersona + personaFee);

        // Internal accounting changed
        assertEq(persona.balance(personaAddr, trader), amount);
        assertEq(persona.supply(personaAddr), amount);

        // Nonce must increment
        assertEq(persona.nonces(trader), 1);
    }

    // ---------------------------------------------------------
    // 4. Wrong nonce should revert with InvalidNonce
    // ---------------------------------------------------------
    function testBuyWithWrongNonce_Reverts() public {
        uint256 amount = 1;
        uint256 rewardRatio = 0.1 ether;

        uint256 price = persona.getBuyPrice(personaAddr, amount);
        uint256 rawProtocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 personaFee = (price * personaOwnerFeeRate) / 1 ether;
        uint256 totalCost = price + rawProtocolFee + personaFee;

        // Contract expects nonce == 0, we pass 1
        uint256 wrongNonce = 1;

        bytes memory sig = _signReward(address(persona), trader, rewardRatio, wrongNonce);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(HoldingRewardsBase.InvalidNonce.selector));
        persona.buy{value: totalCost}(personaAddr, amount, rewardRatio, wrongNonce, sig);
    }

    // ---------------------------------------------------------
    // 5. Wrong signer should revert with InvalidVerifier
    // ---------------------------------------------------------
    function testBuyWithWrongVerifierReverts() public {
        uint256 amount = 1;
        uint256 rewardRatio = 0.1 ether;

        uint256 price = persona.getBuyPrice(personaAddr, amount);
        uint256 rawProtocolFee = (price * protocolFeeRate) / 1 ether;
        uint256 personaFee = (price * personaOwnerFeeRate) / 1 ether;
        uint256 totalCost = price + rawProtocolFee + personaFee;

        // Sign with a different private key
        uint256 otherPk = 0xBEEF;
        bytes32 hash = keccak256(abi.encodePacked(address(persona), block.chainid, trader, rewardRatio, uint256(0)));
        bytes32 ethSigned = hash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherPk, ethSigned);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(HoldingRewardsBase.InvalidVerifier.selector));
        persona.buy{value: totalCost}(personaAddr, amount, rewardRatio, 0, sig);
    }

    // ---------------------------------------------------------
    // 6. Buy then sell (with reward) and check state transitions
    // ---------------------------------------------------------
    function testSellWithReward() public {
        uint256 buyAmount = 10;
        uint256 sellAmount = 4;
        uint256 rewardRatio = 0.15 ether; // 15%

        // First, buy without reward to acquire balance
        {
            vm.prank(trader);
            uint256 price = persona.getBuyPrice(personaAddr, buyAmount);
            uint256 rawProtocolFee = (price * protocolFeeRate) / 1 ether;
            uint256 personaFeeBuy = (price * personaOwnerFeeRate) / 1 ether; // renamed to avoid shadowing
            uint256 totalCost = price + rawProtocolFee + personaFeeBuy;

            vm.prank(trader);
            persona.buy{value: totalCost}(personaAddr, buyAmount, 0, 0, "");
        }

        assertEq(persona.balance(personaAddr, trader), buyAmount);
        assertEq(persona.supply(personaAddr), buyAmount);

        // Now sell with a reward signature
        uint256 priceSell = persona.getSellPrice(personaAddr, sellAmount);
        uint256 rawProtocolFeeSell = (priceSell * protocolFeeRate) / 1 ether;
        uint256 personaBaseFeeSell = (priceSell * personaOwnerFeeRate) / 1 ether;

        uint256 nonce = 0;
        bytes memory sig = _signReward(address(persona), trader, rewardRatio, nonce);

        uint256 holdingReward = (rawProtocolFeeSell * rewardRatio) / 1 ether;
        uint256 protocolFee = rawProtocolFeeSell - holdingReward;
        uint256 personaFee = personaBaseFeeSell + holdingReward;
        uint256 proceeds = priceSell - protocolFee - personaFee;

        uint256 beforeTrader = trader.balance;
        uint256 beforeProtocol = protocolFeeRecipient.balance;
        uint256 beforePersona = personaAddr.balance;

        vm.prank(trader);
        persona.sell(personaAddr, sellAmount, rewardRatio, nonce, sig);

        // Balances updated
        assertEq(persona.balance(personaAddr, trader), buyAmount - sellAmount);
        assertEq(persona.supply(personaAddr), buyAmount - sellAmount);

        // Fee transfer checks
        assertEq(protocolFeeRecipient.balance, beforeProtocol + protocolFee);
        assertEq(personaAddr.balance, beforePersona + personaFee);

        // Trader receives proceeds (we use >= because of gas cost)
        assertGe(trader.balance, beforeTrader + proceeds - 1 ether);

        // Nonce incremented
        assertEq(persona.nonces(trader), 1);
    }
}
