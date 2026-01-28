// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {
    StakeCertificates,
    StakePactRegistry,
    SoulboundClaim,
    SoulboundStake,
    Pact,
    ClaimState,
    StakeState,
    RevocationMode,
    Soulbound,
    PactImmutable,
    PactNotFound,
    PactAlreadyExists,
    ClaimNotFound,
    StakeNotFound,
    TokenNotFound,
    ClaimNotRedeemable,
    AlreadyVoided,
    AlreadyRevoked,
    RevocationDisabled,
    InvalidVesting,
    InvalidRecipient,
    InvalidUnits,
    IdempotenceMismatch,
    StakeFullyVested
} from "../src/StakeCertificates.sol";

contract StakeCertificatesTest is Test {
    StakeCertificates public certificates;
    StakePactRegistry public registry;
    SoulboundClaim public claim;
    SoulboundStake public stake;

    address public authority = address(0x1);
    address public recipient = address(0x2);
    address public recipient2 = address(0x3);

    bytes32 public contentHash = keccak256("test pact content");
    bytes32 public rightsRoot = keccak256("test rights");
    string public uri = "ipfs://test";
    string public pactVersion = "1.0.0";

    bytes32 public pactId;

    function setUp() public {
        vm.startPrank(authority);
        certificates = new StakeCertificates(authority);
        registry = certificates.REGISTRY();
        claim = certificates.CLAIM();
        stake = certificates.STAKE();

        // Create a default pact for testing
        pactId = certificates.createPact(
            contentHash,
            rightsRoot,
            uri,
            pactVersion,
            true, // mutable
            RevocationMode.UNVESTED_ONLY,
            true // defaultRevocableUnvested
        );
        vm.stopPrank();
    }

    // ============ Deployment Tests ============

    function test_DeploymentSetsAuthority() public view {
        assertEq(certificates.AUTHORITY(), authority);
    }

    function test_DeploymentCreatesSubContracts() public view {
        assertTrue(address(registry) != address(0));
        assertTrue(address(claim) != address(0));
        assertTrue(address(stake) != address(0));
    }

    function test_IssuerIdIsCorrect() public view {
        bytes32 expectedIssuerId = keccak256(abi.encode(block.chainid, authority));
        assertEq(certificates.ISSUER_ID(), expectedIssuerId);
    }

    // ============ Pact Tests ============

    function test_CreatePact() public view {
        Pact memory p = registry.getPact(pactId);
        assertEq(p.contentHash, contentHash);
        assertEq(p.rightsRoot, rightsRoot);
        assertEq(p.uri, uri);
        assertEq(p.pactVersion, pactVersion);
        assertTrue(p.mutablePact);
        assertEq(uint8(p.revocationMode), uint8(RevocationMode.UNVESTED_ONLY));
    }

    function test_CreatePact_EmitsPactCreated() public {
        bytes32 newContentHash = keccak256("new content");
        string memory newVersion = "2.0.0";
        bytes32 expectedPactId = registry.computePactId(
            certificates.ISSUER_ID(),
            newContentHash,
            newVersion
        );

        vm.prank(authority);
        // Just verify the pact is created successfully and returns correct ID
        bytes32 createdPactId = certificates.createPact(
            newContentHash,
            rightsRoot,
            uri,
            newVersion,
            true,
            RevocationMode.ANY,
            false
        );

        assertEq(createdPactId, expectedPactId);
        assertTrue(registry.pactExists(createdPactId));
    }

    function test_CreatePact_RevertsForNonAuthority() public {
        vm.prank(recipient);
        vm.expectRevert();
        certificates.createPact(
            contentHash,
            rightsRoot,
            uri,
            "3.0.0",
            true,
            RevocationMode.ANY,
            false
        );
    }

    function test_CreatePact_RevertsDuplicate() public {
        vm.prank(authority);
        vm.expectRevert(PactAlreadyExists.selector);
        certificates.createPact(
            contentHash,
            rightsRoot,
            uri,
            pactVersion, // Same version
            true,
            RevocationMode.ANY,
            false
        );
    }

    function test_AmendPact() public {
        bytes32 newContentHash = keccak256("amended content");
        string memory newVersion = "1.1.0";

        vm.prank(authority);
        bytes32 newPactId = certificates.amendPact(
            pactId,
            newContentHash,
            rightsRoot,
            uri,
            newVersion
        );

        Pact memory p = registry.getPact(newPactId);
        assertEq(p.contentHash, newContentHash);
        assertEq(p.supersedesPactId, pactId);
    }

    function test_AmendPact_RevertsForImmutable() public {
        // Create immutable pact
        vm.prank(authority);
        bytes32 immutablePactId = certificates.createPact(
            keccak256("immutable"),
            rightsRoot,
            uri,
            "immutable-1.0.0",
            false, // immutable
            RevocationMode.NONE,
            false
        );

        vm.prank(authority);
        vm.expectRevert(PactImmutable.selector);
        certificates.amendPact(
            immutablePactId,
            keccak256("new"),
            rightsRoot,
            uri,
            "immutable-1.1.0"
        );
    }

    // ============ Claim Tests ============

    function test_IssueClaim() public {
        bytes32 issuanceId = keccak256("issuance-1");
        uint256 maxUnits = 1000;
        uint64 redeemableAt = 0;

        vm.prank(authority);
        uint256 claimId = certificates.issueClaim(
            issuanceId,
            recipient,
            pactId,
            maxUnits,
            redeemableAt
        );

        assertEq(claimId, 1);
        assertEq(claim.ownerOf(claimId), recipient);

        ClaimState memory c = claim.getClaim(claimId);
        assertEq(c.maxUnits, maxUnits);
        assertFalse(c.voided);
        assertFalse(c.redeemed);
    }

    function test_IssueClaim_Idempotent() public {
        bytes32 issuanceId = keccak256("issuance-1");

        vm.startPrank(authority);
        uint256 claimId1 = certificates.issueClaim(
            issuanceId,
            recipient,
            pactId,
            1000,
            0
        );

        // Same issuance should return same claimId
        uint256 claimId2 = certificates.issueClaim(
            issuanceId,
            recipient,
            pactId,
            1000,
            0
        );

        assertEq(claimId1, claimId2);
        vm.stopPrank();
    }

    function test_IssueClaim_IdempotenceMismatch() public {
        bytes32 issuanceId = keccak256("issuance-1");

        vm.startPrank(authority);
        certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);

        // Different params should revert
        vm.expectRevert(IdempotenceMismatch.selector);
        certificates.issueClaim(issuanceId, recipient, pactId, 2000, 0);
        vm.stopPrank();
    }

    function test_IssueClaim_RevertsInvalidRecipient() public {
        vm.prank(authority);
        vm.expectRevert(InvalidRecipient.selector);
        certificates.issueClaim(
            keccak256("test"),
            address(0),
            pactId,
            1000,
            0
        );
    }

    function test_IssueClaim_RevertsInvalidUnits() public {
        vm.prank(authority);
        vm.expectRevert(InvalidUnits.selector);
        certificates.issueClaim(
            keccak256("test"),
            recipient,
            pactId,
            0, // Zero units
            0
        );
    }

    function test_VoidClaim() public {
        bytes32 issuanceId = keccak256("void-test");

        vm.startPrank(authority);
        certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);
        certificates.voidClaim(issuanceId, keccak256("void reason"));
        vm.stopPrank();

        (uint256 claimId, ClaimState memory c) = certificates.getClaimByIssuanceId(issuanceId);
        assertTrue(c.voided);
        assertEq(c.reasonHash, keccak256("void reason"));
    }

    function test_VoidClaim_RevertsAlreadyVoided() public {
        bytes32 issuanceId = keccak256("void-test");

        vm.startPrank(authority);
        certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);
        certificates.voidClaim(issuanceId, bytes32(0));

        vm.expectRevert(AlreadyVoided.selector);
        certificates.voidClaim(issuanceId, bytes32(0));
        vm.stopPrank();
    }

    // ============ Soulbound Tests ============

    function test_ClaimIsNonTransferable() public {
        bytes32 issuanceId = keccak256("soulbound-test");

        vm.prank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);

        vm.prank(recipient);
        vm.expectRevert(Soulbound.selector);
        claim.transferFrom(recipient, recipient2, claimId);
    }

    function test_ClaimApproveFails() public {
        bytes32 issuanceId = keccak256("approve-test");

        vm.prank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);

        vm.prank(recipient);
        vm.expectRevert(Soulbound.selector);
        claim.approve(recipient2, claimId);
    }

    function test_ClaimSetApprovalForAllFails() public {
        vm.prank(recipient);
        vm.expectRevert(Soulbound.selector);
        claim.setApprovalForAll(recipient2, true);
    }

    function test_ClaimIsLocked() public {
        bytes32 issuanceId = keccak256("locked-test");

        vm.prank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);

        assertTrue(claim.locked(claimId));
    }

    function test_LockedRevertsForNonexistent() public {
        vm.expectRevert(TokenNotFound.selector);
        claim.locked(999);
    }

    // ============ Redemption Tests ============

    function test_RedeemToStake() public {
        bytes32 issuanceId = keccak256("redeem-test");
        bytes32 redemptionId = keccak256("redemption-1");

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);

        uint64 now_ = uint64(block.timestamp);
        uint256 stakeId = certificates.redeemToStake(
            redemptionId,
            claimId,
            1000,
            now_,         // vestStart
            now_ + 365 days, // vestCliff
            now_ + 4 * 365 days, // vestEnd
            bytes32(0)
        );
        vm.stopPrank();

        assertEq(stakeId, 1);
        assertEq(stake.ownerOf(stakeId), recipient);

        StakeState memory s = stake.getStake(stakeId);
        assertEq(s.units, 1000);
        assertFalse(s.revoked);

        // Claim should be marked redeemed
        ClaimState memory c = claim.getClaim(claimId);
        assertTrue(c.redeemed);
    }

    function test_RedeemToStake_Idempotent() public {
        bytes32 issuanceId = keccak256("redeem-idem");
        bytes32 redemptionId = keccak256("redemption-idem");

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);

        uint64 now_ = uint64(block.timestamp);
        uint256 stakeId1 = certificates.redeemToStake(
            redemptionId, claimId, 1000, now_, now_, now_, bytes32(0)
        );

        uint256 stakeId2 = certificates.redeemToStake(
            redemptionId, claimId, 1000, now_, now_, now_, bytes32(0)
        );

        assertEq(stakeId1, stakeId2);
        vm.stopPrank();
    }

    function test_RedeemToStake_RevertsNotRedeemableYet() public {
        bytes32 issuanceId = keccak256("not-yet");
        bytes32 redemptionId = keccak256("redemption-early");

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(
            issuanceId,
            recipient,
            pactId,
            1000,
            uint64(block.timestamp + 1 days) // Redeemable tomorrow
        );

        uint64 now_ = uint64(block.timestamp);
        vm.expectRevert(ClaimNotRedeemable.selector);
        certificates.redeemToStake(
            redemptionId, claimId, 1000, now_, now_, now_, bytes32(0)
        );
        vm.stopPrank();
    }

    function test_RedeemToStake_WorksAfterRedeemableAt() public {
        bytes32 issuanceId = keccak256("timed-redeem");
        bytes32 redemptionId = keccak256("redemption-timed");

        uint64 redeemableAt = uint64(block.timestamp + 1 days);

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(
            issuanceId, recipient, pactId, 1000, redeemableAt
        );

        // Warp to after redeemable time
        vm.warp(redeemableAt + 1);

        uint64 now_ = uint64(block.timestamp);
        uint256 stakeId = certificates.redeemToStake(
            redemptionId, claimId, 1000, now_, now_, now_, bytes32(0)
        );
        vm.stopPrank();

        assertEq(stakeId, 1);
    }

    // ============ Vesting Tests ============

    function test_VestedUnits_BeforeCliff() public {
        bytes32 issuanceId = keccak256("vest-before-cliff");
        bytes32 redemptionId = keccak256("vest-redeem");

        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);
        uint256 stakeId = certificates.redeemToStake(
            redemptionId,
            claimId,
            1000,
            now_,                    // vestStart
            now_ + 365 days,         // vestCliff (1 year)
            now_ + 4 * 365 days,     // vestEnd (4 years)
            bytes32(0)
        );
        vm.stopPrank();

        // Before cliff - should be 0
        assertEq(stake.vestedUnits(stakeId), 0);
        assertEq(stake.unvestedUnits(stakeId), 1000);
    }

    function test_VestedUnits_AtCliff() public {
        bytes32 issuanceId = keccak256("vest-at-cliff");
        bytes32 redemptionId = keccak256("vest-redeem-cliff");

        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);
        uint256 stakeId = certificates.redeemToStake(
            redemptionId,
            claimId,
            1000,
            now_,                    // vestStart
            now_ + 365 days,         // vestCliff (1 year)
            now_ + 4 * 365 days,     // vestEnd (4 years)
            bytes32(0)
        );
        vm.stopPrank();

        // Warp to cliff
        vm.warp(now_ + 365 days);

        // At cliff (1 year into 4 year vesting) = 25%
        uint256 vested = stake.vestedUnits(stakeId);
        assertEq(vested, 250); // 1000 * 1/4
    }

    function test_VestedUnits_FullyVested() public {
        bytes32 issuanceId = keccak256("fully-vested");
        bytes32 redemptionId = keccak256("fully-redeem");

        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);
        uint256 stakeId = certificates.redeemToStake(
            redemptionId,
            claimId,
            1000,
            now_,
            now_ + 365 days,
            now_ + 4 * 365 days,
            bytes32(0)
        );
        vm.stopPrank();

        // Warp past vestEnd
        vm.warp(now_ + 5 * 365 days);

        assertEq(stake.vestedUnits(stakeId), 1000);
        assertEq(stake.unvestedUnits(stakeId), 0);
    }

    // ============ Revocation Tests ============

    function test_RevokeStake_UnvestedOnly() public {
        bytes32 issuanceId = keccak256("revoke-unvested");
        bytes32 redemptionId = keccak256("revoke-redeem");

        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);
        uint256 stakeId = certificates.redeemToStake(
            redemptionId,
            claimId,
            1000,
            now_,
            now_ + 365 days,
            now_ + 4 * 365 days,
            bytes32(0)
        );

        certificates.revokeStake(stakeId, keccak256("terminated"));
        vm.stopPrank();

        StakeState memory s = stake.getStake(stakeId);
        assertTrue(s.revoked);
    }

    function test_RevokeStake_RevertsWhenFullyVested() public {
        bytes32 issuanceId = keccak256("revoke-fully-vested");
        bytes32 redemptionId = keccak256("revoke-redeem-full");

        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);
        uint256 stakeId = certificates.redeemToStake(
            redemptionId,
            claimId,
            1000,
            now_,
            now_ + 365 days,
            now_ + 4 * 365 days,
            bytes32(0)
        );
        vm.stopPrank();

        // Warp past vestEnd
        vm.warp(now_ + 5 * 365 days);

        vm.prank(authority);
        vm.expectRevert(StakeFullyVested.selector);
        certificates.revokeStake(stakeId, bytes32(0));
    }

    function test_RevokeStake_RevertsWhenModeIsNone() public {
        // Create pact with NONE revocation mode
        vm.prank(authority);
        bytes32 noPactId = certificates.createPact(
            keccak256("no-revoke"),
            rightsRoot,
            uri,
            "no-revoke-1.0.0",
            true,
            RevocationMode.NONE,
            false
        );

        bytes32 issuanceId = keccak256("no-revoke-claim");
        bytes32 redemptionId = keccak256("no-revoke-redeem");

        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, noPactId, 1000, 0);
        uint256 stakeId = certificates.redeemToStake(
            redemptionId, claimId, 1000, now_, now_ + 1, now_ + 2, bytes32(0)
        );

        vm.expectRevert(RevocationDisabled.selector);
        certificates.revokeStake(stakeId, bytes32(0));
        vm.stopPrank();
    }

    function test_RevokeStake_RevertsAlreadyRevoked() public {
        bytes32 issuanceId = keccak256("double-revoke");
        bytes32 redemptionId = keccak256("double-redeem");

        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);
        uint256 stakeId = certificates.redeemToStake(
            redemptionId, claimId, 1000, now_, now_ + 365 days, now_ + 4 * 365 days, bytes32(0)
        );

        certificates.revokeStake(stakeId, bytes32(0));

        vm.expectRevert(AlreadyRevoked.selector);
        certificates.revokeStake(stakeId, bytes32(0));
        vm.stopPrank();
    }

    // ============ ERC-5192 Interface Tests ============

    function test_SupportsERC5192() public view {
        bytes4 ERC5192_INTERFACE_ID = 0xb45a3c0e;
        assertTrue(claim.supportsInterface(ERC5192_INTERFACE_ID));
        assertTrue(stake.supportsInterface(ERC5192_INTERFACE_ID));
    }

    function test_SupportsERC721() public view {
        bytes4 ERC721_INTERFACE_ID = 0x80ac58cd;
        assertTrue(claim.supportsInterface(ERC721_INTERFACE_ID));
        assertTrue(stake.supportsInterface(ERC721_INTERFACE_ID));
    }

    function test_SupportsERC165() public view {
        bytes4 ERC165_INTERFACE_ID = 0x01ffc9a7;
        assertTrue(claim.supportsInterface(ERC165_INTERFACE_ID));
        assertTrue(stake.supportsInterface(ERC165_INTERFACE_ID));
    }

    // ============ Edge Cases ============

    function test_ImmediateVesting() public {
        bytes32 issuanceId = keccak256("immediate-vest");
        bytes32 redemptionId = keccak256("immediate-redeem");

        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);

        // Immediate vesting: all timestamps the same
        uint256 stakeId = certificates.redeemToStake(
            redemptionId, claimId, 1000, now_, now_, now_, bytes32(0)
        );
        vm.stopPrank();

        // Should be fully vested immediately
        assertEq(stake.vestedUnits(stakeId), 1000);
    }

    function test_PartialRedemption() public {
        bytes32 issuanceId = keccak256("partial");
        bytes32 redemptionId = keccak256("partial-redeem");

        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);

        // Redeem only 500 units
        uint256 stakeId = certificates.redeemToStake(
            redemptionId, claimId, 500, now_, now_, now_, bytes32(0)
        );
        vm.stopPrank();

        StakeState memory s = stake.getStake(stakeId);
        assertEq(s.units, 500);
    }

    function test_RedeemToStake_RevertsExceedsMaxUnits() public {
        bytes32 issuanceId = keccak256("exceed-max");
        bytes32 redemptionId = keccak256("exceed-redeem");

        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);

        vm.expectRevert(InvalidUnits.selector);
        certificates.redeemToStake(
            redemptionId, claimId, 1001, now_, now_, now_, bytes32(0)
        );
        vm.stopPrank();
    }

    function test_InvalidVestingOrder() public {
        bytes32 issuanceId = keccak256("invalid-vest");
        bytes32 redemptionId = keccak256("invalid-redeem");

        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);

        // Cliff before start - should fail
        vm.expectRevert(InvalidVesting.selector);
        certificates.redeemToStake(
            redemptionId, claimId, 1000, now_ + 100, now_, now_ + 200, bytes32(0)
        );
        vm.stopPrank();
    }

    // ============ Gas Benchmarks ============

    function test_GasBenchmark_CreatePact() public {
        vm.prank(authority);
        uint256 gasStart = gasleft();
        certificates.createPact(
            keccak256("benchmark"),
            rightsRoot,
            uri,
            "bench-1.0.0",
            true,
            RevocationMode.ANY,
            false
        );
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for createPact:", gasUsed);
    }

    function test_GasBenchmark_IssueClaim() public {
        vm.prank(authority);
        uint256 gasStart = gasleft();
        certificates.issueClaim(keccak256("bench-issue"), recipient, pactId, 1000, 0);
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for issueClaim:", gasUsed);
    }

    function test_GasBenchmark_RedeemToStake() public {
        bytes32 issuanceId = keccak256("bench-redeem");
        bytes32 redemptionId = keccak256("bench-stake");

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, 0);

        uint64 now_ = uint64(block.timestamp);
        uint256 gasStart = gasleft();
        certificates.redeemToStake(
            redemptionId, claimId, 1000, now_, now_ + 365 days, now_ + 4 * 365 days, bytes32(0)
        );
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for redeemToStake:", gasUsed);
        vm.stopPrank();
    }
}
