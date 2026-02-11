// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StakeToken} from "../src/StakeToken.sol";

contract StakeTokenTest is Test {
    StakeToken public token;

    address public vault = address(0x1);
    address public governance = address(0x2);
    address public protocolFee = address(0x3);
    address public recipient = address(0x4);
    address public nobody = address(0x5);

    uint256 public constant INITIAL_SUPPLY = 1_000_000;

    function setUp() public {
        token = new StakeToken("Stake Token", "sTKN", INITIAL_SUPPLY, vault, protocolFee, governance);
    }

    // ============ Governance Mint Tests ============

    function test_GovernanceMint() public {
        vm.prank(governance);
        token.governanceMint(recipient, 1000);
        assertEq(token.balanceOf(recipient), 1000);
    }

    function test_GovernanceMint_RevertsForNonGovernance() public {
        vm.prank(nobody);
        vm.expectRevert();
        token.governanceMint(recipient, 1000);
    }

    function test_GovernanceMint_VaultCannotGovernanceMint() public {
        vm.prank(vault);
        vm.expectRevert();
        token.governanceMint(recipient, 1000);
    }

    function test_GovernanceMint_RespectsAuthorizedSupply() public {
        vm.prank(governance);
        vm.expectRevert(StakeToken.ExceedsAuthorizedSupply.selector);
        token.governanceMint(recipient, INITIAL_SUPPLY + 1);
    }

    function test_GovernanceMint_AfterSupplyIncrease() public {
        vm.startPrank(governance);

        // Mint up to current cap
        token.governanceMint(recipient, INITIAL_SUPPLY);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);

        // Can't mint more
        vm.expectRevert(StakeToken.ExceedsAuthorizedSupply.selector);
        token.governanceMint(recipient, 1);

        // Raise the cap
        token.setAuthorizedSupply(INITIAL_SUPPLY * 2);

        // Now can mint
        token.governanceMint(recipient, 500_000);
        assertEq(token.balanceOf(recipient), INITIAL_SUPPLY + 500_000);

        vm.stopPrank();
    }

    function test_GovernanceMint_CoexistsWithVaultMint() public {
        // Vault mints some
        vm.prank(vault);
        token.mint(recipient, 400_000);

        // Governance mints some
        vm.prank(governance);
        token.governanceMint(recipient, 400_000);

        // Both count against authorized supply
        assertEq(token.totalSupply(), 800_000);
        assertEq(token.balanceOf(recipient), 800_000);

        // Remaining capacity is 200_000
        vm.prank(governance);
        vm.expectRevert(StakeToken.ExceedsAuthorizedSupply.selector);
        token.governanceMint(recipient, 200_001);
    }

    // ============ Authorized Supply Tests ============

    function test_SetAuthorizedSupply() public {
        vm.prank(governance);
        token.setAuthorizedSupply(2_000_000);
        assertEq(token.authorizedSupply(), 2_000_000);
    }

    function test_SetAuthorizedSupply_RevertsForNonGovernance() public {
        vm.prank(nobody);
        vm.expectRevert();
        token.setAuthorizedSupply(2_000_000);
    }

    function test_SetAuthorizedSupply_CannotSetBelowTotalSupply() public {
        vm.prank(vault);
        token.mint(recipient, 500_000);

        vm.prank(governance);
        vm.expectRevert(StakeToken.InvalidSupply.selector);
        token.setAuthorizedSupply(499_999);
    }

    // ============ Lockup Tests ============

    function test_Lockup_BlocksTransfer() public {
        vm.prank(vault);
        token.mint(recipient, 1000);

        vm.prank(vault);
        token.setLockup(recipient, uint64(block.timestamp + 90 days));

        vm.prank(recipient);
        vm.expectRevert(StakeToken.TokensLocked.selector);
        token.transfer(nobody, 100);
    }

    function test_Lockup_AllowsWhitelistedDestination() public {
        vm.prank(vault);
        token.mint(recipient, 1000);

        vm.prank(vault);
        token.setLockup(recipient, uint64(block.timestamp + 90 days));

        // Transfer to vault (whitelisted) should work
        vm.prank(recipient);
        token.transfer(vault, 100);
        assertEq(token.balanceOf(vault), 100);
    }

    function test_Lockup_ExpiresAfterDuration() public {
        vm.prank(vault);
        token.mint(recipient, 1000);

        vm.prank(vault);
        token.setLockup(recipient, uint64(block.timestamp + 90 days));

        vm.warp(block.timestamp + 91 days);

        vm.prank(recipient);
        token.transfer(nobody, 100);
        assertEq(token.balanceOf(nobody), 100);
    }

    // ============ Governance Balance Tests ============

    function test_GovernanceBalance_ExcludesProtocolFee() public {
        vm.prank(vault);
        token.mint(protocolFee, 10_000);

        assertEq(token.balanceOf(protocolFee), 10_000);
        assertEq(token.governanceBalance(protocolFee), 0);
    }

    function test_GovernanceBalance_NormalHolder() public {
        vm.prank(vault);
        token.mint(recipient, 10_000);

        assertEq(token.governanceBalance(recipient), 10_000);
    }
}
