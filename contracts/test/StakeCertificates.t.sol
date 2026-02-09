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
    UnitType,
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
    StakeFullyVested,
    AlreadyTransitioned,
    InvalidVault,
    InvalidAuthority,
    ArrayLengthMismatch
} from "../src/StakeCertificates.sol";

contract StakeCertificatesTest is Test {
    StakeCertificates public certificates;
    StakePactRegistry public registry;
    SoulboundClaim public claim;
    SoulboundStake public stake;

    address public authority = address(0x1);
    address public recipient = address(0x2);
    address public recipient2 = address(0x3);
    address public vaultAddr = address(0x4);

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

    // ============ Helper ============

    function _issueClaim(bytes32 issuanceId, address to, uint256 maxUnits) internal returns (uint256) {
        return certificates.issueClaim(issuanceId, to, pactId, maxUnits, UnitType.SHARES, 0);
    }

    function _issueAndRedeem(
        bytes32 issuanceId,
        bytes32 redemptionId,
        address to,
        uint256 units,
        uint64 vestStart,
        uint64 vestCliff,
        uint64 vestEnd
    )
        internal
        returns (uint256 claimId, uint256 stakeId)
    {
        claimId = _issueClaim(issuanceId, to, units);
        stakeId = certificates.redeemToStake(
            redemptionId, claimId, units, UnitType.SHARES, vestStart, vestCliff, vestEnd, bytes32(0)
        );
    }

    // ============ Deployment Tests ============

    function test_DeploymentSetsAuthority() public view {
        assertEq(certificates.authority(), authority);
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
        bytes32 expectedPactId = registry.computePactId(certificates.ISSUER_ID(), newContentHash, newVersion);

        vm.prank(authority);
        bytes32 createdPactId =
            certificates.createPact(newContentHash, rightsRoot, uri, newVersion, true, RevocationMode.ANY, false);

        assertEq(createdPactId, expectedPactId);
        assertTrue(registry.pactExists(createdPactId));
    }

    function test_CreatePact_RevertsForNonAuthority() public {
        vm.prank(recipient);
        vm.expectRevert();
        certificates.createPact(contentHash, rightsRoot, uri, "3.0.0", true, RevocationMode.ANY, false);
    }

    function test_CreatePact_RevertsDuplicate() public {
        vm.prank(authority);
        vm.expectRevert(PactAlreadyExists.selector);
        certificates.createPact(contentHash, rightsRoot, uri, pactVersion, true, RevocationMode.ANY, false);
    }

    function test_AmendPact() public {
        bytes32 newContentHash = keccak256("amended content");
        string memory newVersion = "1.1.0";

        vm.prank(authority);
        bytes32 newPactId = certificates.amendPact(pactId, newContentHash, rightsRoot, uri, newVersion);

        Pact memory p = registry.getPact(newPactId);
        assertEq(p.contentHash, newContentHash);
        assertEq(p.supersedesPactId, pactId);
    }

    function test_AmendPact_RevertsForImmutable() public {
        vm.prank(authority);
        bytes32 immutablePactId = certificates.createPact(
            keccak256("immutable"), rightsRoot, uri, "immutable-1.0.0", false, RevocationMode.NONE, false
        );

        vm.prank(authority);
        vm.expectRevert(PactImmutable.selector);
        certificates.amendPact(immutablePactId, keccak256("new"), rightsRoot, uri, "immutable-1.1.0");
    }

    // ============ tryGetPact Tests (L-4 Fix) ============

    function test_TryGetPact_ExistingPact() public view {
        (bool exists, Pact memory p) = registry.tryGetPact(pactId);
        assertTrue(exists);
        assertEq(p.contentHash, contentHash);
    }

    function test_TryGetPact_NonexistentPact() public view {
        (bool exists,) = registry.tryGetPact(keccak256("nonexistent"));
        assertFalse(exists);
    }

    // ============ Claim Tests ============

    function test_IssueClaim() public {
        bytes32 issuanceId = keccak256("issuance-1");

        vm.prank(authority);
        uint256 claimId = certificates.issueClaim(issuanceId, recipient, pactId, 1000, UnitType.SHARES, 0);

        assertEq(claimId, 1);
        assertEq(claim.ownerOf(claimId), recipient);

        ClaimState memory c = claim.getClaim(claimId);
        assertEq(c.maxUnits, 1000);
        assertEq(uint8(c.unitType), uint8(UnitType.SHARES));
        assertFalse(c.voided);
        assertFalse(c.fullyRedeemed);
        assertEq(c.redeemedUnits, 0);
    }

    function test_IssueClaim_Idempotent() public {
        bytes32 issuanceId = keccak256("issuance-1");

        vm.startPrank(authority);
        uint256 claimId1 = certificates.issueClaim(issuanceId, recipient, pactId, 1000, UnitType.SHARES, 0);
        uint256 claimId2 = certificates.issueClaim(issuanceId, recipient, pactId, 1000, UnitType.SHARES, 0);

        assertEq(claimId1, claimId2);
        vm.stopPrank();
    }

    function test_IssueClaim_IdempotenceMismatch() public {
        bytes32 issuanceId = keccak256("issuance-1");

        vm.startPrank(authority);
        certificates.issueClaim(issuanceId, recipient, pactId, 1000, UnitType.SHARES, 0);

        vm.expectRevert(IdempotenceMismatch.selector);
        certificates.issueClaim(issuanceId, recipient, pactId, 2000, UnitType.SHARES, 0);
        vm.stopPrank();
    }

    function test_IssueClaim_RevertsInvalidRecipient() public {
        vm.prank(authority);
        vm.expectRevert(InvalidRecipient.selector);
        certificates.issueClaim(keccak256("test"), address(0), pactId, 1000, UnitType.SHARES, 0);
    }

    function test_IssueClaim_RevertsInvalidUnits() public {
        vm.prank(authority);
        vm.expectRevert(InvalidUnits.selector);
        certificates.issueClaim(keccak256("test"), recipient, pactId, 0, UnitType.SHARES, 0);
    }

    function test_VoidClaim() public {
        bytes32 issuanceId = keccak256("void-test");

        vm.startPrank(authority);
        certificates.issueClaim(issuanceId, recipient, pactId, 1000, UnitType.SHARES, 0);
        certificates.voidClaim(issuanceId, keccak256("void reason"));
        vm.stopPrank();

        (, ClaimState memory c) = certificates.getClaimByIssuanceId(issuanceId);
        assertTrue(c.voided);
        assertEq(c.reasonHash, keccak256("void reason"));
    }

    function test_VoidClaim_RevertsAlreadyVoided() public {
        bytes32 issuanceId = keccak256("void-test");

        vm.startPrank(authority);
        certificates.issueClaim(issuanceId, recipient, pactId, 1000, UnitType.SHARES, 0);
        certificates.voidClaim(issuanceId, bytes32(0));

        vm.expectRevert(AlreadyVoided.selector);
        certificates.voidClaim(issuanceId, bytes32(0));
        vm.stopPrank();
    }

    // ============ M-1 Fix: Void works regardless of revocationMode ============

    function test_VoidClaim_WorksWhenRevocationModeIsNone() public {
        // Create a pact with NONE revocation mode
        vm.prank(authority);
        bytes32 nonePactId = certificates.createPact(
            keccak256("no-revoke"), rightsRoot, uri, "none-1.0.0", true, RevocationMode.NONE, false
        );

        vm.startPrank(authority);
        uint256 claimId =
            certificates.issueClaim(keccak256("void-none"), recipient, nonePactId, 1000, UnitType.SHARES, 0);
        // Void should succeed even with NONE revocation mode
        certificates.voidClaim(keccak256("void-none"), keccak256("cancelled"));
        vm.stopPrank();

        ClaimState memory c = claim.getClaim(claimId);
        assertTrue(c.voided);
    }

    // ============ Soulbound Tests ============

    function test_ClaimIsNonTransferable() public {
        vm.prank(authority);
        uint256 claimId = _issueClaim(keccak256("soulbound-test"), recipient, 1000);

        vm.prank(recipient);
        vm.expectRevert(Soulbound.selector);
        claim.transferFrom(recipient, recipient2, claimId);
    }

    function test_ClaimApproveFails() public {
        vm.prank(authority);
        uint256 claimId = _issueClaim(keccak256("approve-test"), recipient, 1000);

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
        vm.prank(authority);
        uint256 claimId = _issueClaim(keccak256("locked-test"), recipient, 1000);
        assertTrue(claim.locked(claimId));
    }

    function test_LockedRevertsForNonexistent() public {
        vm.expectRevert(TokenNotFound.selector);
        claim.locked(999);
    }

    // ============ Redemption Tests ============

    function test_RedeemToStake() public {
        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = _issueClaim(keccak256("redeem-test"), recipient, 1000);
        uint256 stakeId = certificates.redeemToStake(
            keccak256("redemption-1"),
            claimId,
            1000,
            UnitType.SHARES,
            now_,
            now_ + 365 days,
            now_ + 4 * 365 days,
            bytes32(0)
        );
        vm.stopPrank();

        assertEq(stakeId, 1);
        assertEq(stake.ownerOf(stakeId), recipient);

        StakeState memory s = stake.getStake(stakeId);
        assertEq(s.units, 1000);
        assertEq(uint8(s.unitType), uint8(UnitType.SHARES));
        assertFalse(s.revoked);
        assertEq(s.revokedUnits, 0);
        assertEq(s.revokedAt, 0);

        ClaimState memory c = claim.getClaim(claimId);
        assertTrue(c.fullyRedeemed);
        assertEq(c.redeemedUnits, 1000);
    }

    function test_RedeemToStake_Idempotent() public {
        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = _issueClaim(keccak256("redeem-idem"), recipient, 1000);
        uint256 stakeId1 = certificates.redeemToStake(
            keccak256("redemption-idem"), claimId, 1000, UnitType.SHARES, now_, now_, now_, bytes32(0)
        );
        uint256 stakeId2 = certificates.redeemToStake(
            keccak256("redemption-idem"), claimId, 1000, UnitType.SHARES, now_, now_, now_, bytes32(0)
        );

        assertEq(stakeId1, stakeId2);
        vm.stopPrank();
    }

    function test_RedeemToStake_RevertsNotRedeemableYet() public {
        uint64 now_ = uint64(block.timestamp);

        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(
            keccak256("not-yet"), recipient, pactId, 1000, UnitType.SHARES, uint64(block.timestamp + 1 days)
        );

        vm.expectRevert(ClaimNotRedeemable.selector);
        certificates.redeemToStake(keccak256("early"), claimId, 1000, UnitType.SHARES, now_, now_, now_, bytes32(0));
        vm.stopPrank();
    }

    function test_RedeemToStake_WorksAfterRedeemableAt() public {
        uint64 redeemableAt = uint64(block.timestamp + 1 days);

        vm.startPrank(authority);
        uint256 claimId =
            certificates.issueClaim(keccak256("timed-redeem"), recipient, pactId, 1000, UnitType.SHARES, redeemableAt);

        vm.warp(redeemableAt + 1);
        uint64 now_ = uint64(block.timestamp);
        uint256 stakeId = certificates.redeemToStake(
            keccak256("timed"), claimId, 1000, UnitType.SHARES, now_, now_, now_, bytes32(0)
        );
        vm.stopPrank();

        assertEq(stakeId, 1);
    }

    // ============ Partial Redemption Tests (H-1 Fix) ============

    function test_PartialRedemption() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        uint256 claimId = _issueClaim(keccak256("partial"), recipient, 1000);

        // Redeem 500 of 1000
        uint256 stakeId1 = certificates.redeemToStake(
            keccak256("partial-redeem-1"), claimId, 500, UnitType.SHARES, now_, now_, now_, bytes32(0)
        );

        // Verify claim is not fully redeemed
        ClaimState memory c = claim.getClaim(claimId);
        assertFalse(c.fullyRedeemed);
        assertEq(c.redeemedUnits, 500);
        assertEq(claim.remainingUnits(claimId), 500);

        // Redeem remaining 500
        uint256 stakeId2 = certificates.redeemToStake(
            keccak256("partial-redeem-2"), claimId, 500, UnitType.SHARES, now_, now_, now_, bytes32(0)
        );
        vm.stopPrank();

        // Now claim is fully redeemed
        ClaimState memory c2 = claim.getClaim(claimId);
        assertTrue(c2.fullyRedeemed);
        assertEq(c2.redeemedUnits, 1000);

        // Two separate stakes created
        StakeState memory s1 = stake.getStake(stakeId1);
        StakeState memory s2 = stake.getStake(stakeId2);
        assertEq(s1.units, 500);
        assertEq(s2.units, 500);
    }

    function test_PartialRedemption_RevertsExceedsRemaining() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        uint256 claimId = _issueClaim(keccak256("exceed-remaining"), recipient, 1000);

        // Redeem 700
        certificates.redeemToStake(keccak256("exceed-r1"), claimId, 700, UnitType.SHARES, now_, now_, now_, bytes32(0));

        // Try to redeem 400 more (only 300 remaining)
        vm.expectRevert(InvalidUnits.selector);
        certificates.redeemToStake(keccak256("exceed-r2"), claimId, 400, UnitType.SHARES, now_, now_, now_, bytes32(0));
        vm.stopPrank();
    }

    function test_PartialRedemption_RevertsAfterFullyRedeemed() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        uint256 claimId = _issueClaim(keccak256("full-then-more"), recipient, 1000);

        // Redeem all
        certificates.redeemToStake(keccak256("full-r1"), claimId, 1000, UnitType.SHARES, now_, now_, now_, bytes32(0));

        // Try to redeem more
        vm.expectRevert(ClaimNotRedeemable.selector);
        certificates.redeemToStake(keccak256("full-r2"), claimId, 1, UnitType.SHARES, now_, now_, now_, bytes32(0));
        vm.stopPrank();
    }

    // ============ Vesting Tests ============

    function test_VestedUnits_BeforeCliff() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        (, uint256 stakeId) = _issueAndRedeem(
            keccak256("vest-before-cliff"),
            keccak256("vest-redeem"),
            recipient,
            1000,
            now_,
            now_ + 365 days,
            now_ + 4 * 365 days
        );
        vm.stopPrank();

        assertEq(stake.vestedUnits(stakeId), 0);
        assertEq(stake.unvestedUnits(stakeId), 1000);
    }

    function test_VestedUnits_AtCliff() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        (, uint256 stakeId) = _issueAndRedeem(
            keccak256("vest-at-cliff"),
            keccak256("vest-redeem-cliff"),
            recipient,
            1000,
            now_,
            now_ + 365 days,
            now_ + 4 * 365 days
        );
        vm.stopPrank();

        vm.warp(now_ + 365 days);
        assertEq(stake.vestedUnits(stakeId), 250);
    }

    function test_VestedUnits_FullyVested() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        (, uint256 stakeId) = _issueAndRedeem(
            keccak256("fully-vested"),
            keccak256("fully-redeem"),
            recipient,
            1000,
            now_,
            now_ + 365 days,
            now_ + 4 * 365 days
        );
        vm.stopPrank();

        vm.warp(now_ + 5 * 365 days);
        assertEq(stake.vestedUnits(stakeId), 1000);
        assertEq(stake.unvestedUnits(stakeId), 0);
    }

    // ============ Revocation Tests (C-3, C-4 Fixes) ============

    function test_RevokeStake_UnvestedOnly_ReducesUnits() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        (, uint256 stakeId) = _issueAndRedeem(
            keccak256("revoke-unvested"),
            keccak256("revoke-redeem"),
            recipient,
            1000,
            now_,
            now_ + 365 days,
            now_ + 4 * 365 days
        );

        // Warp to 2 years (50% vested)
        vm.warp(now_ + 2 * 365 days);

        certificates.revokeStake(stakeId, keccak256("terminated"));
        vm.stopPrank();

        StakeState memory s = stake.getStake(stakeId);
        assertTrue(s.revoked);
        assertEq(s.units, 500); // Retained vested units
        assertEq(s.revokedUnits, 500); // Revoked unvested units
        assertEq(s.revokedAt, uint64(now_ + 2 * 365 days));
    }

    function test_RevokeStake_VestedUnitsFreeze() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        (, uint256 stakeId) = _issueAndRedeem(
            keccak256("revoke-freeze"),
            keccak256("revoke-freeze-r"),
            recipient,
            1000,
            now_,
            now_ + 365 days,
            now_ + 4 * 365 days
        );

        // Revoke at day 0 (before cliff → 0 vested)
        certificates.revokeStake(stakeId, bytes32(0));
        vm.stopPrank();

        // Vesting should be frozen at 0
        assertEq(stake.vestedUnits(stakeId), 0);

        // Even after time passes, vesting stays frozen
        vm.warp(now_ + 5 * 365 days);
        assertEq(stake.vestedUnits(stakeId), 0);
        assertEq(stake.unvestedUnits(stakeId), 0);

        StakeState memory s = stake.getStake(stakeId);
        assertEq(s.units, 0);
        assertEq(s.revokedUnits, 1000);
    }

    function test_RevokeStake_ANY_RevokesEverything() public {
        // Create pact with ANY revocation mode
        vm.prank(authority);
        bytes32 anyPactId = certificates.createPact(
            keccak256("any-revoke"), rightsRoot, uri, "any-1.0.0", true, RevocationMode.ANY, true
        );

        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        uint256 claimId =
            certificates.issueClaim(keccak256("any-claim"), recipient, anyPactId, 1000, UnitType.SHARES, 0);

        // Warp to 50% vested
        vm.warp(now_ + 2 * 365 days);

        uint256 stakeId = certificates.redeemToStake(
            keccak256("any-redeem"),
            claimId,
            1000,
            UnitType.SHARES,
            now_,
            now_ + 365 days,
            now_ + 4 * 365 days,
            bytes32(0)
        );

        certificates.revokeStake(stakeId, keccak256("any revoke"));
        vm.stopPrank();

        StakeState memory s = stake.getStake(stakeId);
        assertTrue(s.revoked);
        assertEq(s.units, 0); // Everything revoked
        assertEq(s.revokedUnits, 1000); // All units revoked
    }

    function test_RevokeStake_RevertsWhenFullyVested() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        (, uint256 stakeId) = _issueAndRedeem(
            keccak256("revoke-fully-vested"),
            keccak256("revoke-redeem-full"),
            recipient,
            1000,
            now_,
            now_ + 365 days,
            now_ + 4 * 365 days
        );
        vm.stopPrank();

        vm.warp(now_ + 5 * 365 days);

        vm.prank(authority);
        vm.expectRevert(StakeFullyVested.selector);
        certificates.revokeStake(stakeId, bytes32(0));
    }

    function test_RevokeStake_RevertsWhenModeIsNone() public {
        vm.prank(authority);
        bytes32 noPactId = certificates.createPact(
            keccak256("no-revoke"), rightsRoot, uri, "no-revoke-1.0.0", true, RevocationMode.NONE, false
        );

        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        uint256 claimId =
            certificates.issueClaim(keccak256("no-revoke-claim"), recipient, noPactId, 1000, UnitType.SHARES, 0);
        uint256 stakeId = certificates.redeemToStake(
            keccak256("no-revoke-redeem"), claimId, 1000, UnitType.SHARES, now_, now_ + 1, now_ + 2, bytes32(0)
        );

        vm.expectRevert(RevocationDisabled.selector);
        certificates.revokeStake(stakeId, bytes32(0));
        vm.stopPrank();
    }

    function test_RevokeStake_RevertsAlreadyRevoked() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        (, uint256 stakeId) = _issueAndRedeem(
            keccak256("double-revoke"),
            keccak256("double-redeem"),
            recipient,
            1000,
            now_,
            now_ + 365 days,
            now_ + 4 * 365 days
        );

        certificates.revokeStake(stakeId, bytes32(0));

        vm.expectRevert(AlreadyRevoked.selector);
        certificates.revokeStake(stakeId, bytes32(0));
        vm.stopPrank();
    }

    // ============ Pause Tests (C-1 Fix) ============

    function test_Pause_BlocksIssuance() public {
        vm.startPrank(authority);
        certificates.pause();

        vm.expectRevert();
        certificates.issueClaim(keccak256("paused"), recipient, pactId, 1000, UnitType.SHARES, 0);
        vm.stopPrank();
    }

    function test_Pause_BlocksPactCreation() public {
        vm.startPrank(authority);
        certificates.pause();

        vm.expectRevert();
        certificates.createPact(keccak256("paused"), rightsRoot, uri, "paused-1.0", true, RevocationMode.ANY, false);
        vm.stopPrank();
    }

    function test_Unpause_RestoresOperations() public {
        vm.startPrank(authority);
        certificates.pause();
        certificates.unpause();

        // Should work after unpause
        uint256 claimId = _issueClaim(keccak256("unpaused"), recipient, 1000);
        assertEq(claimId, 1);
        vm.stopPrank();
    }

    // ============ Authority Rotation Tests (H-4 Fix) ============

    function test_TransferAuthority() public {
        address newAuthority = address(0x99);

        vm.prank(authority);
        certificates.transferAuthority(newAuthority);

        assertEq(certificates.authority(), newAuthority);

        // New authority can create pacts
        vm.prank(newAuthority);
        bytes32 newPact =
            certificates.createPact(keccak256("new-auth"), rightsRoot, uri, "2.0.0", true, RevocationMode.ANY, false);
        assertTrue(registry.pactExists(newPact));
    }

    function test_TransferAuthority_OldAuthorityLosesAccess() public {
        address newAuthority = address(0x99);

        vm.prank(authority);
        certificates.transferAuthority(newAuthority);

        // Old authority can no longer create pacts
        vm.prank(authority);
        vm.expectRevert();
        certificates.createPact(keccak256("old-auth"), rightsRoot, uri, "3.0.0", true, RevocationMode.ANY, false);
    }

    function test_TransferAuthority_RevertsZeroAddress() public {
        vm.prank(authority);
        vm.expectRevert(InvalidAuthority.selector);
        certificates.transferAuthority(address(0));
    }

    function test_TransferAuthority_RegistryNotDirectlyAccessible() public {
        // Authority EOA should NOT have direct admin on the registry
        bytes32 operatorRole = registry.OPERATOR_ROLE();
        bytes32 adminRole = registry.DEFAULT_ADMIN_ROLE();

        // Authority is not registry admin — StakeCertificates is
        assertFalse(registry.hasRole(adminRole, authority));
        assertTrue(registry.hasRole(adminRole, address(certificates)));

        // Authority cannot grant operator role on registry directly
        vm.prank(authority);
        vm.expectRevert();
        registry.grantRole(operatorRole, recipient);
    }

    function test_TransferAuthority_RevertsPostTransition() public {
        vm.startPrank(authority);
        certificates.initiateTransition(vaultAddr);

        // Authority roles revoked at transition — can't transfer
        vm.expectRevert();
        certificates.transferAuthority(address(0x99));
        vm.stopPrank();
    }

    // ============ Base URI Tests (H-3 Fix) ============

    function test_SetClaimBaseURI() public {
        vm.prank(authority);
        certificates.setClaimBaseURI("https://api.stake.com/claims/");

        vm.prank(authority);
        uint256 claimId = _issueClaim(keccak256("uri-test"), recipient, 1000);

        assertEq(claim.tokenURI(claimId), "https://api.stake.com/claims/1");
    }

    function test_SetStakeBaseURI() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        certificates.setStakeBaseURI("https://api.stake.com/stakes/");
        (, uint256 stakeId) =
            _issueAndRedeem(keccak256("uri-stake"), keccak256("uri-stake-r"), recipient, 1000, now_, now_, now_);
        vm.stopPrank();

        assertEq(stake.tokenURI(stakeId), "https://api.stake.com/stakes/1");
    }

    // ============ Batch Issuance Tests (M-3 Fix) ============

    function test_IssueClaimBatch() public {
        bytes32[] memory issuanceIds = new bytes32[](3);
        issuanceIds[0] = keccak256("batch-1");
        issuanceIds[1] = keccak256("batch-2");
        issuanceIds[2] = keccak256("batch-3");

        address[] memory recipients_ = new address[](3);
        recipients_[0] = recipient;
        recipients_[1] = recipient2;
        recipients_[2] = address(0x5);

        uint256[] memory maxUnitsArr = new uint256[](3);
        maxUnitsArr[0] = 1000;
        maxUnitsArr[1] = 2000;
        maxUnitsArr[2] = 3000;

        vm.prank(authority);
        uint256[] memory claimIds =
            certificates.issueClaimBatch(issuanceIds, recipients_, pactId, maxUnitsArr, UnitType.SHARES, 0);

        assertEq(claimIds.length, 3);
        assertEq(claim.ownerOf(claimIds[0]), recipient);
        assertEq(claim.ownerOf(claimIds[1]), recipient2);
        assertEq(claim.ownerOf(claimIds[2]), address(0x5));

        ClaimState memory c = claim.getClaim(claimIds[1]);
        assertEq(c.maxUnits, 2000);
    }

    // ============ Transition Tests ============

    function test_InitiateTransition() public {
        vm.prank(authority);
        certificates.initiateTransition(vaultAddr);

        assertTrue(certificates.transitioned());
    }

    function test_InitiateTransition_SetsVaultOnChildren() public {
        vm.prank(authority);
        certificates.initiateTransition(vaultAddr);

        assertEq(claim.vault(), vaultAddr);
        assertEq(stake.vault(), vaultAddr);
    }

    function test_InitiateTransition_FreezesIssuerPowers() public {
        vm.startPrank(authority);
        certificates.initiateTransition(vaultAddr);

        // Authority roles are revoked at transition — AccessControl fires before whenNotTransitioned
        vm.expectRevert();
        certificates.createPact(keccak256("post"), rightsRoot, uri, "post-1.0", true, RevocationMode.ANY, false);

        vm.expectRevert();
        certificates.issueClaim(keccak256("post"), recipient, pactId, 1000, UnitType.SHARES, 0);

        // Verify authority has no roles
        assertFalse(certificates.hasRole(certificates.AUTHORITY_ROLE(), authority));
        assertFalse(certificates.hasRole(certificates.PAUSER_ROLE(), authority));
        assertFalse(certificates.hasRole(certificates.DEFAULT_ADMIN_ROLE(), authority));
        vm.stopPrank();
    }

    function test_InitiateTransition_RevertsInvalidVault() public {
        vm.prank(authority);
        vm.expectRevert(InvalidVault.selector);
        certificates.initiateTransition(address(0));
    }

    function test_InitiateTransition_RevertsDouble() public {
        vm.startPrank(authority);
        certificates.initiateTransition(vaultAddr);

        // Authority roles revoked — can't call again even if they wanted to
        vm.expectRevert();
        certificates.initiateTransition(vaultAddr);
        vm.stopPrank();
    }

    // ============ Vault Transfer Tests ============

    function test_VaultCanTransferStake() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        (, uint256 stakeId) =
            _issueAndRedeem(keccak256("vault-xfer"), keccak256("vault-xfer-r"), recipient, 1000, now_, now_, now_);
        certificates.initiateTransition(vaultAddr);
        vm.stopPrank();

        // Vault can now transfer the stake
        vm.prank(vaultAddr);
        stake.transferFrom(recipient, vaultAddr, stakeId);

        assertEq(stake.ownerOf(stakeId), vaultAddr);
    }

    function test_NonVaultCannotTransferStake() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        (, uint256 stakeId) =
            _issueAndRedeem(keccak256("no-xfer"), keccak256("no-xfer-r"), recipient, 1000, now_, now_, now_);
        certificates.initiateTransition(vaultAddr);
        vm.stopPrank();

        // Random address still can't transfer
        vm.prank(recipient);
        vm.expectRevert(Soulbound.selector);
        stake.transferFrom(recipient, recipient2, stakeId);
    }

    function test_PauseRevertsPostTransition() public {
        vm.startPrank(authority);
        certificates.initiateTransition(vaultAddr);

        // Authority can't pause post-transition — roles revoked
        vm.expectRevert();
        certificates.pause();
        vm.stopPrank();
    }

    function test_VaultTransferWorksPostTransition() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        (, uint256 stakeId) =
            _issueAndRedeem(keccak256("vault-post"), keccak256("vault-post-r"), recipient, 1000, now_, now_, now_);
        certificates.initiateTransition(vaultAddr);
        vm.stopPrank();

        // Vault transfers are unstoppable post-transition
        vm.prank(vaultAddr);
        stake.transferFrom(recipient, vaultAddr, stakeId);
        assertEq(stake.ownerOf(stakeId), vaultAddr);
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
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        (, uint256 stakeId) = _issueAndRedeem(
            keccak256("immediate-vest"), keccak256("immediate-redeem"), recipient, 1000, now_, now_, now_
        );
        vm.stopPrank();

        assertEq(stake.vestedUnits(stakeId), 1000);
    }

    function test_RedeemToStake_RevertsExceedsMaxUnits() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        uint256 claimId = _issueClaim(keccak256("exceed-max"), recipient, 1000);

        vm.expectRevert(InvalidUnits.selector);
        certificates.redeemToStake(
            keccak256("exceed-redeem"), claimId, 1001, UnitType.SHARES, now_, now_, now_, bytes32(0)
        );
        vm.stopPrank();
    }

    function test_InvalidVestingOrder() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        uint256 claimId = _issueClaim(keccak256("invalid-vest"), recipient, 1000);

        vm.expectRevert(InvalidVesting.selector);
        certificates.redeemToStake(
            keccak256("invalid-redeem"), claimId, 1000, UnitType.SHARES, now_ + 100, now_, now_ + 200, bytes32(0)
        );
        vm.stopPrank();
    }

    // ============ UnitType Tests (H-1 Fix) ============

    function test_UnitType_StoredOnClaim() public {
        vm.prank(authority);
        uint256 claimId = certificates.issueClaim(keccak256("bps-claim"), recipient, pactId, 5000, UnitType.BPS, 0);

        ClaimState memory c = claim.getClaim(claimId);
        assertEq(uint8(c.unitType), uint8(UnitType.BPS));
    }

    function test_UnitType_StoredOnStake() public {
        uint64 now_ = uint64(block.timestamp);
        vm.startPrank(authority);
        uint256 claimId = certificates.issueClaim(keccak256("wei-claim"), recipient, pactId, 1e18, UnitType.WEI, 0);
        uint256 stakeId = certificates.redeemToStake(
            keccak256("wei-redeem"), claimId, 1e18, UnitType.WEI, now_, now_, now_, bytes32(0)
        );
        vm.stopPrank();

        StakeState memory s = stake.getStake(stakeId);
        assertEq(uint8(s.unitType), uint8(UnitType.WEI));
    }

    // ============ Gas Benchmarks ============

    function test_GasBenchmark_CreatePact() public {
        vm.prank(authority);
        uint256 gasStart = gasleft();
        certificates.createPact(keccak256("benchmark"), rightsRoot, uri, "bench-1.0.0", true, RevocationMode.ANY, false);
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for createPact:", gasUsed);
    }

    function test_GasBenchmark_IssueClaim() public {
        vm.prank(authority);
        uint256 gasStart = gasleft();
        certificates.issueClaim(keccak256("bench-issue"), recipient, pactId, 1000, UnitType.SHARES, 0);
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for issueClaim:", gasUsed);
    }

    function test_GasBenchmark_RedeemToStake() public {
        vm.startPrank(authority);
        uint256 claimId = _issueClaim(keccak256("bench-redeem"), recipient, 1000);

        uint64 now_ = uint64(block.timestamp);
        uint256 gasStart = gasleft();
        certificates.redeemToStake(
            keccak256("bench-stake"),
            claimId,
            1000,
            UnitType.SHARES,
            now_,
            now_ + 365 days,
            now_ + 4 * 365 days,
            bytes32(0)
        );
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for redeemToStake:", gasUsed);
        vm.stopPrank();
    }
}
