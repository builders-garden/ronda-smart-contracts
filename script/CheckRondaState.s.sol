// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {RondaProtocol, VerificationType} from "../src/RondaProtocol.sol";

/**
 * @title CheckRondaState
 * @notice Script to check the state and configuration of a deployed RondaProtocol contract
 * @dev Usage:
 *  1. Set RONDA_ADDRESS environment variable:
 *     export RONDA_ADDRESS=0x...
 *  
 *  2. Run the script:
 *     forge script script/CheckRondaState.s.sol:CheckRondaState \
 *       --rpc-url https://forno.celo.org
 */
contract CheckRondaState is Script {
    function run() external view {
        // Get RondaProtocol address from environment (required)
        address rondaAddress = 0x724b4f9AaAF6620c3bD11Bb66D2BE0fA432d5234;
        require(rondaAddress != address(0), "RONDA_ADDRESS must be set");
        
        console.log("\n=== RondaProtocol Contract State ===");
        console.log("Contract Address:", rondaAddress);
        console.log("Chain ID:", block.chainid);
        
        // Get contract instance
        RondaProtocol ronda = RondaProtocol(rondaAddress);
        
        // Basic Info
        console.log("\n--- Basic Information ---");
        console.log("Group ID:", ronda.groupId());
        
        // Try to get ENS name (new contracts have this, old contracts don't)
        try ronda.groupEnsName() returns (string memory ensName) {
            console.log("Group ENS Name:", ensName);
        } catch {
            console.log("Group ENS Name: Not available (old contract version)");
        }
        
        console.log("Creator:", ronda.creator());
        
        // Try to get operator (new contracts)
        try ronda.operator() returns (address operatorAddr) {
            console.log("Operator:", operatorAddr);
        } catch {
            console.log("Operator: Not available (old contract version)");
        }
        console.log("USDC Address:", address(ronda.usdc()));
        console.log("Aave Pool Address:", address(ronda.aavePool()));
        console.log("Aave USDC Address:", address(ronda.aaveUsdc()));
        console.log("Fee Recipient:", ronda.feeRecipient());
        
        // Group Configuration
        console.log("\n--- Group Configuration ---");
        (
            address creator,
            VerificationType verificationType,
            uint256 depositFrequency,
            uint256 borrowFrequency,
            uint256 recurringAmount,
            uint256 operationCounter,
            uint256 currentOperationIndex,
            uint256 lastDepositTime,
            uint256 lastBorrowTime,
            uint256 minAge,
            string[] memory allowedNationalities,
            string memory requiredGender
        ) = ronda.getGroupInfo();
        
        console.log("Creator:", creator);
        console.log("Verification Type:", uint256(verificationType), _verificationTypeToString(verificationType));
        console.log("Deposit Frequency (seconds):", depositFrequency);
        console.log("Deposit Frequency (days):", depositFrequency / 1 days);
        console.log("Borrow Frequency (seconds):", borrowFrequency);
        console.log("Borrow Frequency (days):", borrowFrequency / 1 days);
        console.log("Recurring Amount:", recurringAmount);
        console.log("Recurring Amount (USDC):", recurringAmount / 1e6);
        console.log("Operation Counter:", operationCounter);
        console.log("Current Operation Index:", currentOperationIndex);
        console.log("Last Deposit Time:", lastDepositTime);
        console.log("Last Deposit Time (readable):", _timestampToString(lastDepositTime));
        console.log("Last Borrow Time:", lastBorrowTime);
        console.log("Last Borrow Time (readable):", _timestampToString(lastBorrowTime));
        console.log("Min Age:", minAge);
        console.log("Required Gender:", requiredGender);
        
        // Allowed Nationalities
        console.log("\n--- Allowed Nationalities ---");
        if (allowedNationalities.length == 0) {
            console.log("No nationality restrictions (empty array)");
        } else {
            console.log("Count:", allowedNationalities.length);
            for (uint256 i = 0; i < allowedNationalities.length; i++) {
                console.log("  [%s]: %s", i, allowedNationalities[i]);
            }
        }
        
        // Detailed Group Info
        console.log("\n--- Detailed Group Information ---");
        (
            address _creator,
            VerificationType _verificationType,
            uint256 _depositFrequency,
            uint256 _borrowFrequency,
            uint256 _recurringAmount,
            uint256 _operationCounter,
            uint256 _currentOperationIndex,
            uint256 _lastDepositTime,
            uint256 _lastBorrowTime,
            uint256 _minAge,
            string[] memory _allowedNationalities,
            string memory _requiredGender,
            uint256 currentPeriodDeposits,
            bool exists
        ) = ronda.getGroupInfoDetailed();
        
        console.log("Group Exists:", exists);
        console.log("Current Period Deposits:", currentPeriodDeposits);
        console.log("Current Period Deposits (USDC):", currentPeriodDeposits / 1e6);
        
        // Period Deposits
        console.log("\n--- Period Deposits ---");
        for (uint256 i = 0; i < _operationCounter; i++) {
            uint256 deposits = ronda.getPeriodDeposits(i);
            if (deposits > 0 || i == _currentOperationIndex) {
                console.log("Period [%s]: %s USDC (%s)", i, deposits / 1e6, deposits);
            }
        }
        
        // Verification Config
        console.log("\n--- Verification Configuration ---");
        console.log("Verification Config ID:", vm.toString(ronda.verificationConfigId()));
        
        // Check if we can get more info about verification config
        try ronda.verificationConfig() returns (
            bool olderThanEnabled,
            uint256 olderThan,
            bool forbiddenCountriesEnabled
        ) {
            console.log("Older Than Enabled:", olderThanEnabled);
            console.log("Older Than:", olderThan);
            console.log("Forbidden Countries Enabled:", forbiddenCountriesEnabled);
        } catch {
            console.log("Could not read verification config details");
        }
        
        // Token Balances
        console.log("\n--- Token Balances ---");
        try ronda.usdc().balanceOf(rondaAddress) returns (uint256 usdcBalance) {
            console.log("USDC Balance in Contract:", usdcBalance);
            console.log("USDC Balance (formatted):", usdcBalance / 1e6, "USDC");
        } catch {
            console.log("Could not read USDC balance");
        }
        
        try ronda.aaveUsdc().balanceOf(rondaAddress) returns (uint256 aaveUsdcBalance) {
            console.log("aUSDC Balance in Contract:", aaveUsdcBalance);
            console.log("aUSDC Balance (formatted):", aaveUsdcBalance / 1e6, "aUSDC");
        } catch {
            console.log("Could not read aUSDC balance");
        }
        
        // Optional: Check specific user status (if USER_ADDRESS env var is set)
        try vm.envAddress("USER_ADDRESS") returns (address userAddress) {
            console.log("\n--- User Status (", userAddress, ") ---");
            console.log("Is Member:", ronda.isMember(userAddress));
            console.log("Is Invited:", ronda.isInvited(userAddress));
            
            // Check if user is verified
            bool isVerified = ronda.isUserVerified(userAddress);
            console.log("Is Verified:", isVerified);
            if (!isVerified && ronda.verificationType() != VerificationType.NONE) {
                console.log("  WARNING: User is not verified but verification is required for this group");
            }
            
            // Check deposit status for current period
            bool depositedCurrent = ronda.hasUserDepositedCurrentPeriod(userAddress);
            console.log("Deposited in Current Period:", depositedCurrent);
            
            // Get deposit status for all periods
            (bool[] memory depositedPeriods, uint256 totalPeriods) = ronda.getUserDepositStatusForAllPeriods(userAddress);
            console.log("Deposit Status Across All Periods:");
            for (uint256 i = 0; i < totalPeriods; i++) {
                console.log("  Period [%s]: %s", i, depositedPeriods[i] ? "Deposited" : "Not Deposited");
            }
        } catch {
            // USER_ADDRESS not set, skip user-specific checks
            console.log("\n--- User Status ---");
            console.log("No USER_ADDRESS provided. Set USER_ADDRESS env var to check specific user status.");
            console.log("Example: export USER_ADDRESS=0x...");
        }
        
        console.log("\n=== State Check Complete ===");
    }
    
    /**
     * @notice Converts VerificationType enum to string
     */
    function _verificationTypeToString(VerificationType vType) internal pure returns (string memory) {
        if (vType == VerificationType.NONE) return "NONE";
        if (vType == VerificationType.SELF_BASE) return "SELF_BASE";
        if (vType == VerificationType.SELF_AGE) return "SELF_AGE";
        if (vType == VerificationType.SELF_NATIONALITY) return "SELF_NATIONALITY";
        if (vType == VerificationType.SELF_GENDER) return "SELF_GENDER";
        if (vType == VerificationType.SELF_AGE_NATIONALITY) return "SELF_AGE_NATIONALITY";
        if (vType == VerificationType.SELF_AGE_GENDER) return "SELF_AGE_GENDER";
        if (vType == VerificationType.SELF_NATIONALITY_GENDER) return "SELF_NATIONALITY_GENDER";
        if (vType == VerificationType.SELF_ALL) return "SELF_ALL";
        return "UNKNOWN";
    }
    
    /**
     * @notice Converts timestamp to readable string (simplified)
     */
    function _timestampToString(uint256 timestamp) internal view returns (string memory) {
        if (timestamp == 0) {
            return "Not set";
        }
        // Simple conversion - in production you might want more detailed formatting
        uint256 secondsAgo = block.timestamp > timestamp ? block.timestamp - timestamp : 0;
        return string(abi.encodePacked(vm.toString(timestamp), " (", vm.toString(secondsAgo), " seconds ago)"));
    }
}

