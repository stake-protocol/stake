# Protocol Design Decisions

Every design decision in Stake Protocol was stress-tested against real-world corporate law, adversarial scenarios, and four centuries of equity infrastructure. This document records each decision, the rationale behind it, alternatives considered, counterpoints, and how edge cases are resolved.

---

## 1. Soulbound Certificates

**Decision**: All Claims and Stakes are non-transferable ERC-721 tokens implementing ERC-5192 (Minimal Soulbound Interface). They cannot be sold, traded, listed, or transferred between wallets.

**Rationale**: Every pathology of the token economy — pump-and-dump schemes, governance attacks by mercenary capital, founders dumping control — traces back to premature liquidity. Traditional startup equity has always been illiquid by default. Founders can't sell their shares on day one. Employees can't flip options on a secondary market. This is a feature, not a bug. Soulbound certificates encode this 400-year-old principle at the protocol level.

**Alternatives considered**:
- *Transferable with restrictions* (whitelist, time locks): Adds complexity, still enables secondary markets through workarounds (wrapping, OTC desks). Half measures invite regulatory ambiguity.
- *ERC-1155 semi-fungible*: Cheaper gas for batch operations, but loses individual certificate identity. Each Stake represents a specific redemption event with its own reason hash — individual identity matters.

**Counterpoints**:
- "What about estate planning?" — Holder includes wallet keys in their estate plan. Executor operates the wallet directly. The Stake doesn't transfer; the wallet does.
- "What if I lose my keys?" — Same risk as any self-custodied asset. Post-transition, governance can issue compensating tokens to verified beneficiaries. Pre-transition, the authority can issue a replacement Claim→Stake.
- "Employees want liquidity." — They pressure the founder to initiate transition. This is by design: the decision to enable liquidity should be a deliberate, company-wide event (like an IPO), not a series of individual side deals.

---

## 2. Three-Layer Lifecycle: Pact → Claim → Stake

**Decision**: Equity moves through three distinct phases. A Pact defines the legal terms. A Claim is a conditional right (like an option or SAFE). A Stake is unconditional ownership (like issued shares). Each phase has different properties and powers.

**Rationale**: This mirrors how equity actually works. A stock option plan (Pact) defines the terms. Individual option grants (Claims) vest over time and can be revoked. Exercised shares (Stakes) are permanent property. Collapsing these into one layer forces you to choose between flexibility (needed for options) and permanence (needed for shares). Three layers give each phase the right properties.

**Alternatives considered**:
- *Two layers (Pact → Certificate)*: Forces certificates to be both conditional and unconditional. You end up with "vested certificates" and "unvested certificates" that are technically the same token with different states, which is confusing and error-prone.
- *Four layers (add Token)*: Token is the fourth phase, but it's a separate contract (StakeToken + StakeVault). The transition from Stake to Token is a one-way gate triggered by the authority. This is already the design — Token just isn't part of the certificate lifecycle.

**Counterpoints**:
- "Three layers add complexity." — True, but the complexity maps 1:1 to real-world complexity. A simpler model would hide complexity rather than eliminate it, leading to worse edge cases.
- "Why not go straight from Pact to Stake?" — Because founders need the ability to issue conditional rights before those rights become permanent. A SAFE isn't equity; it's a promise of equity. Collapsing the two means either making Stakes revocable (bad for holders) or making Claims irrevocable (bad for founders).

---

## 3. Vesting on Claims, Not Stakes

**Decision**: Vesting schedules (vestStart, vestCliff, vestEnd) live on Claims. Stakes have no vesting — they represent fully vested, unconditional ownership.

**Rationale**: In traditional finance, options vest. Shares don't. Once you exercise an option and receive shares, those shares are yours regardless of what happens next — you get fired, the company pivots, the board changes. Vesting is a condition on the *promise* of ownership, not on ownership itself. Claims are promises. Stakes are ownership. Vesting belongs on promises.

**Alternatives considered**:
- *Vesting on Stakes*: Would mean "you own shares but can't fully use them yet." This doesn't map to any real-world equity instrument. It would create a confusing middle state between conditional and unconditional ownership.
- *Vesting on both*: Double vesting would be confusing and gas-expensive. It would also create questions about which vesting schedule takes precedence.

**Counterpoints**:
- "What about restricted stock?" — Restricted stock IRL vests as shares. But the restriction is actually a *repurchase right*, not a property of the shares themselves. In our model, this maps to: issue a Claim with vesting, redeem to Stake only after vesting. The restriction lives on the Claim.
- "What if you need post-redemption restrictions?" — Those are legal terms in the Pact, enforced off-chain. Once equity is unconditionally yours, any remaining obligations (non-compete, lockup, ROFR) are contractual, not property-level.

---

## 4. Stake Irrevocability

**Decision**: Once a Claim is redeemed to a Stake, no one — not the authority, not the board, not the protocol — can revoke or void that Stake. The only person who can destroy a Stake is its holder (via burn).

**Rationale**: The entire value proposition of onchain equity is removing intermediary risk. If the authority can revoke Stakes, you haven't eliminated the single point of failure — you've just moved it from a SaaS platform to a smart contract. Irrevocability is the strongest possible property right: provably permanent ownership that doesn't depend on anyone's continued goodwill.

By the time something is a Stake, every condition has been satisfied:
1. The authority created the Pact
2. The authority issued the Claim
3. The vesting schedule elapsed
4. The authority approved redemption
5. The units were confirmed as vested

Revoking a Stake would retroactively invalidate this five-step deliberative process.

**Alternatives considered**:
- *Authority-revocable Stakes*: Creates a massive governance attack vector. A compromised board could strip ownership from legitimate holders. A bad-faith founder could issue Stakes, extract work/capital, then revoke.
- *Court-ordered revocation (protocol-level)*: Who decides what constitutes a valid court order? The protocol can't adjudicate law. Adding a "court order" function creates a superuser key that whoever controls it can abuse.
- *Conditional revocation with timelock + multisig*: Still a revocation mechanism. Still attackable. The question isn't "how hard should revocation be?" — it's "should revocation exist at all?" Answer: no.

**Counterpoints**:
- "What about fraud?" — Defend at the Claim layer. Don't redeem Claims from people you suspect of fraud. If fraud is discovered post-Stake, that's a legal matter. Courts can order the holder to burn (see Decision 5).
- "What about fat-finger errors?" — Redemption requires two idempotency checks (issuance ID and redemption ID). Two chances to catch errors. If both fail, the authority can issue compensating Stakes to rebalance. The cost of this workaround is bounded; the cost of adding revocation is unbounded.
- "What about regulatory requirements?" — Pre-transition, keep things as Claims (revocable) until regulatory certainty. Post-transition, compliance mechanisms exist at the token layer. Stakes are the middle ground where confirmed ownership lives.

---

## 5. Holder-Initiated Burn

**Decision**: Stake holders can voluntarily burn (destroy) their own Stakes. No one else can burn a holder's Stake.

**Rationale**: This is the equivalent of share surrender or cancellation in traditional finance. It enables:
- **Voluntary surrender** — Founder gives back shares to simplify cap table
- **Tax write-off** — Write off worthless equity (like Section 165 loss)
- **Court-ordered forfeiture** — Court orders holder to burn; holder complies by calling burnStake
- **Estate cleanup** — Winding down a failed venture
- **Buyback completion** — Company pays holder off-chain, holder burns their Stake

The key property: only the holder can initiate. The authority cannot burn someone else's Stake. This preserves irrevocability from the issuer's perspective while giving holders sovereignty over their own property.

**Alternatives considered**:
- *No burn mechanism*: Simpler, but creates a gap. Court-ordered forfeiture has no on-chain mechanism. Holders who want to surrender equity have no way to do so. Dead equity from failed ventures sits on the ledger forever.
- *Authority-initiated burn*: This is revocation by another name. Rejected for the same reasons.
- *Burn with board approval*: Adds friction to a holder exercising rights over their own property. IRL, you can surrender shares without board approval. The board's role is to govern issuance, not destruction.

**Counterpoints**:
- "Can someone be coerced into burning?" — Yes, but they can be coerced into signing any transaction. This isn't a protocol-level concern. Courts coerce people into transferring property all the time (garnishment, forfeiture). The protocol provides the mechanism; enforcement is legal.
- "Burning reduces total outstanding units — does that affect dilution?" — Yes, same as share cancellation IRL. This is expected behavior, not a bug.
- "What if a holder burns by mistake?" — Irreversible by design. Authority can issue a replacement Claim→Stake if the burn was accidental.

---

## 6. No Secondary Markets Pre-Transition

**Decision**: There is no mechanism for pre-transition liquidity. Stakes cannot be sold, traded, wrapped, or transferred. The only path to liquidity is the authority initiating a transition to tokens.

**Rationale**: Secondary markets for private equity create exactly the problems the thesis identifies. When employees can sell pre-IPO shares on secondary markets (like Carta's CartaX or Forge Global), it creates:
- Price discovery before the company is ready
- Governance fragmentation (buyers have economic interest but no relationship to the company)
- Adverse selection (only disgruntled employees sell, creating a biased signal)
- Regulatory complexity (securities laws apply differently to secondary transfers)

Traditional startups solve this with transfer restrictions on stock certificates (legends). Soulbound certificates are the protocol-level equivalent — you can't sell what you can't transfer.

**Alternatives considered**:
- *Restricted transfers with company consent*: Would recreate the transfer agent model. Adds complexity, creates gatekeeping, and still enables the pathologies above.
- *P2P OTC mechanism with soulbound migration*: Technically possible (burn old Stake, issue new Claim to buyer, redeem to new Stake) but this is just a secondary market with extra steps. Deliberately not implemented.

**Counterpoints**:
- "Series E employees have been waiting 10 years for liquidity." — They pressure the founder to transition. This is the correct incentive alignment: the decision to enable liquidity should be collective, not individual. An employee selling on a secondary market externalizes costs onto other stakeholders.
- "What about divorce settlements?" — Court orders the holder to burn, or the authority issues a compensating Claim→Stake to the ex-spouse. Legal process, not protocol mechanism.

---

## 7. Content-Addressed Pacts

**Decision**: Pact IDs are deterministic hashes of (issuerId, contentHash, pactVersion). The same content always produces the same ID. Duplicate Pact creation reverts.

**Rationale**: Content addressing provides two guarantees:
1. **Integrity** — The Pact ID proves the content hasn't been tampered with. If the off-chain document (on IPFS/Arweave) doesn't hash to the Pact's contentHash, something is wrong.
2. **Deduplication** — You can't accidentally create the same Pact twice. This prevents operational errors where the same agreement is registered multiple times, each spawning its own Claims.

Pacts can be amended (creating a new Pact that supersedes the old one), but only if the original Pact was created with `mutablePact = true`. Immutable Pacts are permanent records that can never be changed — useful for foundational agreements.

**Counterpoints**:
- "What if I need to fix a typo in a Pact URI?" — Amend the Pact. The old version is preserved in the chain of supersessions.
- "What if two different agreements happen to hash to the same ID?" — Astronomically unlikely (keccak256 collision). But even if it happened, the version string differentiates them.

---

## 8. Idempotent Issuance and Redemption

**Decision**: Both `issueClaim` and `redeemToStake` use caller-provided IDs (issuanceId, redemptionId). If the same ID is used twice with identical parameters, the second call returns the existing token without creating a duplicate. If the same ID is used with different parameters, it reverts.

**Rationale**: On-chain transactions can fail and be retried. Without idempotency, a retry could double-issue a Claim or double-redeem a Stake. Idempotency makes retries safe. It also enables off-chain systems (like a cap table management tool) to use their own IDs (e.g., database primary keys) as issuance IDs, creating a clean mapping between off-chain records and on-chain certificates.

The mismatch revert is equally important: if you try to reuse an ID with different parameters, something is wrong in your system. Fail loudly.

**Counterpoints**:
- "Adds gas cost for the mapping." — Yes, but the alternative (duplicate issuance) is far more expensive to fix.
- "What if the off-chain system generates non-unique IDs?" — That's a bug in the off-chain system, not the protocol. The protocol enforces correctness; the caller is responsible for unique IDs.

---

## 9. Board Governance with Timeout Mechanism

**Decision**: StakeBoard implements onchain governance where proposals require quorum approval within a response window. Members who don't respond within the window are excluded from the quorum calculation.

**Rationale**: Traditional board governance has a fundamental problem: non-responsive members can block progress. If quorum is 3 of 5 and two members go dark, nothing gets done — even if the remaining three unanimously agree. The timeout mechanism solves this: after the response window, the adjusted quorum is calculated as `ceil(quorum * responded / totalMembers)`. If 3 of 5 respond and quorum is 60%, the adjusted quorum is `ceil(3 * 3 / 5) = 2` — two of three respondents must approve.

This means: if you care about a decision, respond. If you don't respond, you've implicitly delegated to those who do.

**Alternatives considered**:
- *Simple majority, no timeout*: Non-responsive members permanently block governance. In an onchain context where members might lose access to their wallets, this is a death sentence for the protocol.
- *Off-chain governance (Snapshot-style)*: Defeats the purpose of onchain equity. Governance decisions that affect soulbound certificates should be as verifiable as the certificates themselves.
- *Token-weighted voting*: Plutocratic. The thesis explicitly rejects mercenary governance. Board governance is per-member, not per-dollar.

**Counterpoints**:
- "A hostile majority could rush proposals through before others can respond." — The response window is configurable and should be set long enough for all members to participate (default: 7 days). Proposals can also be rejected or cancelled.
- "What prevents the board from adding compliant members to dilute opposition?" — addMember requires a board proposal itself. Existing members can reject it. If a faction controls quorum, they already control the board — this is a governance capture problem, not a timeout problem.
- "Single founder is the board of one." — Correct. Pre-board, the founder has unilateral authority. This is identical to how sole proprietorships work IRL. Board governance kicks in when outside stakeholders arrive.

---

## 10. Claim Revocation Modes

**Decision**: Each Pact specifies a RevocationMode that applies to all Claims issued under it:
- `NONE` — Claims cannot be revoked (only voided via the safety-valve void function)
- `UNVESTED_ONLY` — Revocation freezes the vesting clock at the current timestamp. Already-vested units remain redeemable. Unvested units are permanently forfeited.
- `ANY` — Revocation voids the entire Claim regardless of vesting status.

Void is a separate, always-available safety valve that destroys the Claim entirely.

**Rationale**: Different equity instruments have different revocation semantics:
- A SAFE typically can't be partially revoked — it either converts or doesn't (NONE or ANY)
- Employee stock options are usually revocable for unvested portions only (UNVESTED_ONLY)
- Advisory shares might be fully revocable if the advisor stops contributing (ANY)

The Pact defines the terms; the protocol enforces them. Founders choose the appropriate mode at Pact creation, and it applies uniformly to all Claims under that Pact.

**The revokedAt mechanism**: When a Claim is revoked under UNVESTED_ONLY, the contract records `revokedAt = block.timestamp`. The vesting calculation uses `min(block.timestamp, revokedAt)` as the effective time, permanently freezing vesting at the revocation point. This is cleaner than splitting the Claim into "vested" and "unvested" portions.

**Counterpoints**:
- "What if the founder wants to change revocation mode after issuance?" — They can't. This is intentional. The revocation mode is a term of the Pact that holders relied on when accepting their Claims. Changing it retroactively would be a bait-and-switch.
- "NONE mode means no recourse against fraud." — Void still works. Void is not revocation — it's a safety valve that exists independently of RevocationMode. A void destroys the Claim, which is appropriate when the Claim itself should never have existed (fraud, duplicate issuance, etc.).

---

## 11. Protocol Fee: 1% at Transition

**Decision**: When Stakes transition to tokens via the StakeVault, a 1% fee is assessed on total token supply. The fee tokens are sent to the ProtocolFeeLiquidator.

**Rationale**: The protocol needs a sustainable revenue model. 1% at transition is:
- **Low friction** — Assessed once, not recurring. No annual fees, no per-transaction fees.
- **Aligned** — Only triggered when the company creates real liquidity for its stakeholders. If the company never transitions, no fee is ever charged. The protocol earns when its users succeed.
- **Comparable** — Traditional transfer agents charge ongoing fees ($5K–$112K/year for Carta). 1% at transition for a $100M company is $1M — less than 10 years of Carta Scale pricing, and it's a one-time cost.

**Counterpoints**:
- "1% is too high for large companies." — A $10B company would pay $100M. This is a valid concern for very large transitions. The fee could be capped, or the protocol could offer negotiated rates. But for the 99% of startups valued under $1B, 1% is reasonable.
- "Why not charge on issuance instead?" — Issuance is a promise, not value creation. Charging on issuance would penalize early-stage companies when they can least afford it.

---

## 12. 90-Day Lockup + 12-Month Permissionless Liquidation

**Decision**: Protocol fee tokens are locked for 90 days after transition, then linearly unlock over 12 months. Anyone can trigger the liquidation — it's permissionless.

**Rationale**: The lockup period prevents the protocol from dumping tokens immediately after transition, which would harm the token price and stakeholders. The 12-month linear unlock ensures gradual sell pressure. Permissionless liquidation means no one needs to trust the protocol team to execute — any address can call `liquidate()` and the tokens are sold through a DEX router at market price.

This is the opposite of a rug pull. The protocol's own fee tokens are time-locked and auto-sold on a predictable schedule. No discretion, no surprises, no insider timing.

**Counterpoints**:
- "What if market conditions are terrible during the 12-month window?" — The protocol accepts market risk, same as any vesting schedule. This is feature parity with how employee equity works — you vest on a schedule regardless of stock price.
- "Permissionless means a bot could front-run liquidations." — The liquidation sells through a router. Sandwich attacks are possible but bounded by the releasable amount. MEV protection (private transactions, DEX-specific protections) can be used by the caller.

---

## 13. Authority Freeze at Transition

**Decision**: When the authority calls `initiateTransition(vault)`, all authority powers are permanently frozen. No more Claims can be issued, no Pacts created, no revocations — nothing. The authority role ceases to function.

**Rationale**: Transition is the moment the company goes from "private equity with a founder in charge" to "public tokens with governance." This is the onchain equivalent of an IPO, where the founder gives up unilateral control. Making the freeze permanent and irrevocable means stakeholders can trust that the rules won't change after they've transitioned their Stakes to tokens.

If the authority retained any powers post-transition, they could:
- Issue new Claims that dilute token holders
- Revoke Claims that were never redeemed
- Amend Pacts retroactively
All of these would undermine trust in the post-transition token.

**Counterpoints**:
- "What if a bug is discovered post-transition?" — The contract is paused/unpausable pre-transition. Post-transition, bug fixes would require a new deployment and migration. This is the cost of immutability, and it's worth it.
- "What if there are unredeemed Claims?" — Holders can still redeem Claims to Stakes post-transition and deposit Stakes into the vault. The authority isn't needed for this — redemption uses existing Claims and follows existing vesting schedules.

---

## 14. Dilution Protection via Board Governance

**Decision**: There is no protocol-level cap on total issuable units. Dilution is controlled by requiring board governance (StakeBoard) for all issuance operations.

**Rationale**: IRL, "authorized shares" in articles of incorporation can be increased by a shareholder/board vote. The cap isn't really a cap — it's a governance checkpoint. StakeBoard provides the same checkpoint: every issuance requires a proposal with quorum approval. Board members representing stakeholders can reject dilutive issuances.

Pre-board (solo founder), there are no dilution protections — and there don't need to be. If you're the only stakeholder, you can't dilute yourself. The moment outside stakeholders arrive, they should require board governance as a condition of accepting Claims.

**Alternatives considered**:
- *Authorized units cap on Pact*: Adds a hard limit. But the limit can be raised by amending the Pact (if mutable), so it's just governance with extra steps. And it creates a new problem: what happens when you hit the cap and need to issue more? You'd need a governance vote to raise it — which is exactly what Board governance already provides.

**Counterpoints**:
- "A founder with no board can dilute everyone." — Same as IRL. A sole proprietor can issue as many shares as they want. The protection is contractual (investor agreements requiring board formation) and legal (fiduciary duty). The protocol can't solve governance problems that the stakeholders haven't opted into solving.

---

## 15. Death and Inheritance

**Decision**: The protocol has no built-in inheritance mechanism. Estate planning is the holder's responsibility. If wallet keys are available, the executor operates the wallet directly. If keys are lost, the authority can issue compensating Stakes to beneficiaries.

**Rationale**: Any on-chain inheritance mechanism requires answering "who decides someone is dead?" — which is a legal question, not a protocol question. Adding a "death oracle" or "beneficiary designation" function creates attack surface (fraudulent death claims, social engineering) that's worse than the problem it solves.

How it works in practice:
1. **Keys available**: Executor uses wallet to participate in governance, receive tokens post-transition, or burn Stakes per court order. No protocol changes needed.
2. **Keys lost, pre-transition**: Authority issues a new Claim→Stake to the beneficiary for the same units. The orphaned Stake inflates total outstanding slightly, but this is manageable.
3. **Keys lost, post-transition**: The orphaned Stake can never be deposited in the vault. Those tokens are effectively locked forever (reducing circulating supply). Governance can vote to issue compensating tokens to beneficiaries.

**Counterpoints**:
- "This is worse than traditional equity, where transfer agents handle inheritance." — True, but traditional equity relies on centralized intermediaries (the exact problem we're solving). The tradeoff is self-sovereignty vs. assisted recovery. We choose self-sovereignty and push recovery to the legal/estate layer.
- "Social recovery contracts could solve this." — Possibly, but that's a wallet-level concern, not a certificate-level concern. If the user's wallet supports social recovery, their Stakes benefit automatically.

---

## 16. ERC-721 Individual Certificates

**Decision**: Each Claim and Stake is an individual ERC-721 token with a unique ID, not a fungible or semi-fungible token.

**Rationale**: Individual certificates preserve provenance. Each Stake traces back to a specific Claim, which traces back to a specific Pact, issuance event, and recipient. This chain of custody is essential for:
- **Audit trails** — Regulators and auditors can trace every certificate to its origin
- **Dispute resolution** — "This Stake was issued under Pact X, issued as Claim Y, redeemed with reason hash Z"
- **Governance** — Post-transition, individual certificates become governance seats (Dutch auction mechanism in StakeVault)

ERC-1155 would be cheaper for batch operations but would lose individual identity. The gas cost difference is acceptable given the high-stakes (pun intended) nature of equity operations — you don't issue equity thousands of times a day.

---

## 17. UnitType Flexibility

**Decision**: Units can be denominated in four types — SHARES, BPS (basis points), WEI, or CUSTOM. The unit type is stored on both Claims and Stakes.

**Rationale**: Not all equity is denominated in shares:
- **SHARES** — Traditional share count (10,000 shares of common stock)
- **BPS** — Basis points of total equity (500 BPS = 5%). Useful for SAFEs and percentage-based agreements where the total share count isn't yet determined.
- **WEI** — Wei-denominated units for token-native equity
- **CUSTOM** — Catch-all for non-standard unit types (profit interest units, carried interest, etc.)

The unit type is carried from Claim to Stake on redemption, preserving the original denomination. Conversion between unit types (e.g., BPS to SHARES when a priced round sets the share count) happens at the application layer, not the protocol layer.

---

## 18. Void as Safety Valve

**Decision**: `voidClaim` is a separate function from `revokeClaim` that always works regardless of RevocationMode. Voiding destroys the Claim entirely — all units, vested and unvested.

**Rationale**: Void exists for situations where the Claim itself should never have existed:
- Fraudulent issuance
- Duplicate issuance (operational error)
- Settlement of disputes

Unlike revocation (which respects the Pact's RevocationMode), void is an authority-level override. It's the "break glass in case of emergency" function.

Why separate from revocation? Because RevocationMode.NONE should mean "normal revocation is not allowed," not "there is absolutely no recourse." A Pact with NONE revocation mode is saying "this Claim vests on schedule and the founder can't claw it back." But if the Claim was issued to the wrong person by mistake, the authority still needs a way to fix it.

**Counterpoints**:
- "Void on a NONE Pact undermines the NONE guarantee." — The distinction is intent. NONE means "the founder won't revoke your vesting." Void means "this Claim was issued in error." Holders of NONE Claims should understand that void is a safety valve, not a backdoor. The reasonHash on void provides an auditable record of why it was used.
- "The authority could abuse void." — True. But the authority can also refuse to redeem Claims or refuse to create Pacts. Pre-transition authority power is inherently broad. That's why the transition freeze exists — it permanently removes the authority's ability to void (or do anything else).
