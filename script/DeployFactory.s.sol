// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {RondaProtocolFactory} from "../src/RondaProtocolFactory.sol";

/**
 * @title DeployFactory2
 * @notice Script to deploy RondaProtocolFactoryEns on Celo with ENS support
 * @dev Usage:
 *  1. Update the address constants below (lines 31-37)
 *  2. Set PRIVATE_KEY environment variable:
 *     export PRIVATE_KEY=your_private_key
 *  
 *  3. For Celo Mainnet:
 *     forge script script/DeployFactory2.s.sol:DeployFactory2 \
 *       --rpc-url https://forno.celo.org \
 *       --broadcast \
 *       --verify \
 *       --etherscan-api-key $CELOSCAN_API_KEY
 *  
 *  4. For Celo Alfajores (testnet):
 *     forge script script/DeployFactory2.s.sol:DeployFactory2 \
 *       --rpc-url https://alfajores-forno.celo-testnet.org \
 *       --broadcast \
 *       --verify \
 *       --etherscan-api-key $CELOSCAN_API_KEY
 */
contract DeployFactory is Script {
    // ============ UPDATE THESE ADDRESSES BEFORE DEPLOYMENT ============
    address constant USDC_ADDRESS = 0xcebA9300f2b948710d2653dD7B07f33A8B32118C; // Celo USDC (cUSD)
    address constant IDENTITY_VERIFICATION_HUB_V2 = 0xe57F4773bd9c9d8b6Cd70431117d353298B9f5BF; // TODO: Add Self Protocol Identity Verification Hub V2 address
    address constant AAVE_POOL_ADDRESS = 0x3E59A31363E2ad014dcbc521c4a0d5757d9f3402; // TODO: Add Aave Pool contract address
    address constant AAVE_USDC_ADDRESS = 0xFF8309b9e99bfd2D4021bc71a362aBD93dBd4785; // TODO: Add Aave aUSDC token address
    address constant FEE_RECIPIENT = 0xf9E987E7FfD88Eed47E30c00504fEfE35F530A4E; // TODO: Add fee recipient address
    address constant OPERATOR = 0xf9E987E7FfD88Eed47E30c00504fEfE35F530A4E; // TODO: Update with actual operator address (authorized to call distributeFunds)
    string constant MAIN_ENS_NAME = "ronda.eth"; // TODO: Update with your main ENS name
    // ===================================================================
    
    function run() external {
        // Get private key from environment (required)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Validate required addresses
        require(USDC_ADDRESS != address(0), "USDC_ADDRESS cannot be zero - update the constant in the script");
        require(IDENTITY_VERIFICATION_HUB_V2 != address(0), "IDENTITY_VERIFICATION_HUB_V2 cannot be zero - update the constant in the script");
        require(AAVE_POOL_ADDRESS != address(0), "AAVE_POOL_ADDRESS cannot be zero - update the constant in the script");
        require(AAVE_USDC_ADDRESS != address(0), "AAVE_USDC_ADDRESS cannot be zero - update the constant in the script");
        require(FEE_RECIPIENT != address(0), "FEE_RECIPIENT cannot be zero - update the constant in the script");
        require(OPERATOR != address(0), "OPERATOR cannot be zero - update the constant in the script");
        require(bytes(MAIN_ENS_NAME).length > 0, "MAIN_ENS_NAME cannot be empty - update the constant in the script");
        
        // Log deployment parameters
        console.log("\n=== Deployment Parameters ===");
        console.log("Deployer address:", deployer);
        console.log("USDC Address:", USDC_ADDRESS);
        console.log("Identity Verification Hub V2:", IDENTITY_VERIFICATION_HUB_V2);
        console.log("Aave Pool Address:", AAVE_POOL_ADDRESS);
        console.log("Aave USDC Address:", AAVE_USDC_ADDRESS);
        console.log("Fee Recipient:", FEE_RECIPIENT);
        console.log("Operator:", OPERATOR);
        console.log("Main ENS Name:", MAIN_ENS_NAME);
        console.log("Note: Factory implements IENSReverseRegistrar and acts as its own registrar");
        console.log("Chain ID:", block.chainid);
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("\nDeploying RondaProtocolFactoryEns...");
        
        // Deploy the factory (factory implements IENSReverseRegistrar itself)
        RondaProtocolFactory factory = new RondaProtocolFactory(
            USDC_ADDRESS,
            IDENTITY_VERIFICATION_HUB_V2,
            AAVE_POOL_ADDRESS,
            AAVE_USDC_ADDRESS,
            FEE_RECIPIENT,
            OPERATOR,
            MAIN_ENS_NAME
        );
        
        vm.stopBroadcast();
        
        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Factory Address:", address(factory));
        console.log("USDC Address:", factory.usdcAddress());
        console.log("Identity Verification Hub V2:", factory.identityVerificationHubV2Address());
        console.log("Aave Pool Address:", factory.aavePoolAddress());
        console.log("Aave USDC Address:", factory.aaveUsdcAddress());
        console.log("Fee Recipient:", factory.feeRecipient());
        console.log("Operator:", factory.operator());
        console.log("Main ENS Name:", factory.mainEnsName());
        console.log("Factory Address (acts as ENS Reverse Registrar):", address(factory));
        console.log("\nDeployment successful!");
    }
}

