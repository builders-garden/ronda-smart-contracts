// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {RondaProtocolFactory, VerificationType} from "../src/RondaProtocolFactory.sol";
import {SelfUtils} from "@selfxyz/contracts/libraries/SelfUtils.sol";

/**
 * @title DeployRonda
 * @notice Script to deploy a RondaProtocol instance via the factory
 * @dev Usage:
 *  1. Set PRIVATE_KEY environment variable:
 *     export PRIVATE_KEY=your_private_key
 *  
 *  2. Optionally set environment variables to override defaults:
 *     export FACTORY_ADDRESS=0x...
 *     export CREATOR=0x...
 *     export DEPOSIT_FREQUENCY=7
 *     export BORROW_FREQUENCY=7
 *     export RECURRING_AMOUNT=1000000
 *     export OPERATION_COUNTER=4
 *     export VERIFICATION_TYPE=0
 *     export MIN_AGE=18
 *     export SCOPE_SEED=ronda-test
 *  
 *  3. Run the script:
 *     forge script script/DeployRonda.s.sol:DeployRonda \
 *       --rpc-url https://forno.celo.org \
 *       --broadcast \
 *       --slow
 */
contract DeployRonda is Script {
    // Default values (from provided JSON)
    // NOTE: FACTORY_ADDRESS must be set via environment variable - no default provided
    address constant DEFAULT_CREATOR = 0x1e4B751B66949b2c48c96a0A28982A2AAEcd605B;
    uint256 constant DEFAULT_DEPOSIT_FREQUENCY = 7 days;
    uint256 constant DEFAULT_BORROW_FREQUENCY = 7 days;
    uint256 constant DEFAULT_RECURRING_AMOUNT = 1000000; // 1 USDC (6 decimals)
    uint256 constant DEFAULT_OPERATION_COUNTER = 4;
    VerificationType constant DEFAULT_VERIFICATION_TYPE = VerificationType.NONE;
    uint256 constant DEFAULT_MIN_AGE = 18;
    string constant DEFAULT_SCOPE_SEED = "ronda-test";
    
    function run() external {
        // Get private key from environment (required)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get factory address (required)
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");
        require(factoryAddress != address(0), "FACTORY_ADDRESS must be set");
        
        // Get deployment parameters from environment or use defaults
        address creator = vm.envOr("CREATOR", DEFAULT_CREATOR);
        
        // Convert days to seconds if provided as days
        uint256 depositFrequency = vm.envOr("DEPOSIT_FREQUENCY", DEFAULT_DEPOSIT_FREQUENCY);
        if (depositFrequency < 86400) {
            // If less than a day, assume it's in days and convert
            depositFrequency = depositFrequency * 1 days;
        }
        
        uint256 borrowFrequency = vm.envOr("BORROW_FREQUENCY", DEFAULT_BORROW_FREQUENCY);
        if (borrowFrequency < 86400) {
            // If less than a day, assume it's in days and convert
            borrowFrequency = borrowFrequency * 1 days;
        }
        
        uint256 recurringAmount = vm.envOr("RECURRING_AMOUNT", DEFAULT_RECURRING_AMOUNT);
        uint256 operationCounter = vm.envOr("OPERATION_COUNTER", DEFAULT_OPERATION_COUNTER);
        
        // Parse verification type (0 = NONE, 1 = SELF_BASE, etc.)
        uint256 verificationTypeUint = vm.envOr("VERIFICATION_TYPE", uint256(DEFAULT_VERIFICATION_TYPE));
        require(verificationTypeUint <= uint256(VerificationType.SELF_ALL), "Invalid verification type");
        VerificationType verificationType = VerificationType(verificationTypeUint);
        
        uint256 minAge = vm.envOr("MIN_AGE", DEFAULT_MIN_AGE);
        string memory scopeSeed = vm.envOr("SCOPE_SEED", DEFAULT_SCOPE_SEED);
        
        // Parse allowed nationalities (comma-separated from env, or empty array)
        string memory allowedNationalitiesStr = vm.envOr("ALLOWED_NATIONALITIES", string(""));
        string[] memory allowedNationalities = _parseStringArray(allowedNationalitiesStr);
        
        string memory requiredGender = vm.envOr("REQUIRED_GENDER", string(""));
        
        // Parse users to invite (comma-separated addresses from env, or empty array)
        string memory usersToInviteStr = vm.envOr("USERS_TO_INVITE", string(""));
        address[] memory usersToInvite;
        if (bytes(usersToInviteStr).length > 0) {
            usersToInvite = _parseAddressArray(usersToInviteStr);
        } else {
            usersToInvite = new address[](0);
        }
        
        // Parse forbidden countries (comma-separated from env, or empty array)
        string memory forbiddenCountriesStr = vm.envOr("FORBIDDEN_COUNTRIES", string(""));
        string[] memory forbiddenCountries = _parseStringArray(forbiddenCountriesStr);
        
        bool ofacEnabled = vm.envOr("OFAC_ENABLED", false);
        
        // Build verification config
        SelfUtils.UnformattedVerificationConfigV2 memory verificationConfig = SelfUtils.UnformattedVerificationConfigV2({
            olderThan: minAge,
            forbiddenCountries: forbiddenCountries,
            ofacEnabled: ofacEnabled
        });
        
        // Build deployment params
        // Get name from environment or use default
        string memory name = vm.envOr("GROUP_NAME", string("group"));
        
        RondaProtocolFactory.DeploymentParams memory params = RondaProtocolFactory.DeploymentParams({
            name: name,
            scopeSeed: scopeSeed,
            verificationConfig: verificationConfig,
            creator: creator,
            depositFrequency: depositFrequency,
            borrowFrequency: borrowFrequency,
            recurringAmount: recurringAmount,
            operationCounter: operationCounter,
            verificationType: verificationType,
            minAge: minAge,
            allowedNationalities: allowedNationalities,
            requiredGender: requiredGender,
            usersToInvite: usersToInvite
        });
        
        // Log deployment parameters
        console.log("\n=== Deployment Parameters ===");
        console.log("Deployer address:", deployer);
        console.log("Factory Address:", factoryAddress);
        console.log("Creator:", creator);
        console.log("Deposit Frequency (seconds):", depositFrequency);
        console.log("Borrow Frequency (seconds):", borrowFrequency);
        console.log("Recurring Amount:", recurringAmount);
        console.log("Operation Counter:", operationCounter);
        console.log("Verification Type:", uint256(verificationType));
        console.log("Min Age:", minAge);
        console.log("Scope Seed:", scopeSeed);
        console.log("Allowed Nationalities Count:", allowedNationalities.length);
        console.log("Required Gender:", requiredGender);
        console.log("Users to Invite Count:", usersToInvite.length);
        console.log("Forbidden Countries Count:", forbiddenCountries.length);
        console.log("OFAC Enabled:", ofacEnabled);
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("\nDeploying RondaProtocol via Factory...");
        
        // Get factory instance
        RondaProtocolFactory factory = RondaProtocolFactory(factoryAddress);
        
        // Deploy the RondaProtocol instance
        (uint256 groupId, address rondaProtocol) = factory.deployRondaProtocol(params);
        
        vm.stopBroadcast();
        
        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Group ID:", groupId);
        console.log("RondaProtocol Address:", rondaProtocol);
        console.log("Factory Address:", factoryAddress);
        console.log("Creator:", creator);
        console.log("\nDeployment successful!");
    }
    
    /**
     * @notice Parses a comma-separated string into a string array
     * @param str The comma-separated string
     * @return The array of strings
     */
    function _parseStringArray(string memory str) internal pure returns (string[] memory) {
        if (bytes(str).length == 0) {
            return new string[](0);
        }
        
        // Count commas to determine array size
        uint256 count = 1;
        bytes memory strBytes = bytes(str);
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == bytes1(",")) {
                count++;
            }
        }
        
        string[] memory result = new string[](count);
        uint256 currentIndex = 0;
        bytes memory current = new bytes(0);
        
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == bytes1(",")) {
                result[currentIndex] = string(current);
                currentIndex++;
                current = new bytes(0);
            } else {
                // Append character
                bytes memory temp = new bytes(current.length + 1);
                for (uint256 j = 0; j < current.length; j++) {
                    temp[j] = current[j];
                }
                temp[current.length] = strBytes[i];
                current = temp;
            }
        }
        
        // Add last element
        if (current.length > 0) {
            result[currentIndex] = string(current);
        }
        
        return result;
    }
    
    /**
     * @notice Parses a comma-separated string of addresses into an address array
     * @param str The comma-separated string of addresses
     * @return The array of addresses
     */
    function _parseAddressArray(string memory str) internal view returns (address[] memory) {
        if (bytes(str).length == 0) {
            return new address[](0);
        }
        
        string[] memory strArray = _parseStringArray(str);
        address[] memory result = new address[](strArray.length);
        
        for (uint256 i = 0; i < strArray.length; i++) {
            // Remove whitespace and convert to address
            string memory trimmed = _trim(strArray[i]);
            result[i] = vm.parseAddress(trimmed);
        }
        
        return result;
    }
    
    /**
     * @notice Trims whitespace from a string (simple implementation)
     */
    function _trim(string memory str) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length == 0) return str;
        
        uint256 start = 0;
        uint256 end = strBytes.length;
        
        // Find start (skip leading whitespace)
        while (start < end && (strBytes[start] == 0x20 || strBytes[start] == 0x09 || strBytes[start] == 0x0A || strBytes[start] == 0x0D)) {
            start++;
        }
        
        // Find end (skip trailing whitespace)
        while (end > start && (strBytes[end - 1] == 0x20 || strBytes[end - 1] == 0x09 || strBytes[end - 1] == 0x0A || strBytes[end - 1] == 0x0D)) {
            end--;
        }
        
        bytes memory result = new bytes(end - start);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = strBytes[start + i];
        }
        
        return string(result);
    }
}

