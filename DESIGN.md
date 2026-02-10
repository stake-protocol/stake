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

**Decision**: When the authority calls `initiateTransition(vault)`, all authority powers over the certificate layer are permanently frozen. No more Claims can be issued, no Pacts created, no revocations — nothing. The authority role on StakeCertificates ceases to function. Equity issuance continues post-transition, but at the token layer under governance control (see Decision 22).

**Rationale**: Transition is the moment the company graduates from "private soulbound certificates managed by a founder" to "public fungible tokens managed by governance." The certificate layer freezes because its job is done — every Pact, Claim, and Stake becomes an immutable historical record of how equity was issued, vested, and redeemed while the company was private.

This is NOT the same as "the company can never issue equity again." Public companies issue equity constantly — RSUs to new hires, secondary offerings, stock splits. The difference is *where* and *how*: pre-transition, the founder issues certificates (Pact → Claim → Stake). Post-transition, governance mints tokens (authorized supply → governanceMint). The issuance mechanism changes; the capability doesn't disappear.

If the certificate layer remained unfrozen post-transition, the authority could:
- Issue new Claims that dilute token holders (bypassing governance)
- Revoke Claims that were never redeemed (retroactive changes)
- Amend Pacts (changing the terms that stakeholders relied on)
All of these would undermine trust in the post-transition token. The freeze guarantees: once you transition, the pre-transition rules are locked in stone.

**Counterpoints**:
- "But public companies still have a CEO and board that issue equity." — Correct. Post-transition, the GOVERNANCE_ROLE on StakeToken controls new issuance. Governance can raise the authorized supply and mint new tokens. This is the equivalent of the board authorizing new share issuance. The founder doesn't lose the ability to propose new equity — they lose the ability to do it unilaterally.
- "What if a bug is discovered post-transition?" — The certificate contracts are immutable post-transition. Bug fixes would require migration. This is the cost of immutability, and it's worth it — the alternative is a mutable equity layer, which is what we're trying to replace.
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

**Decision**: The protocol has no built-in inheritance mechanism. Wallet recovery is handled at the application layer through embedded wallets (see Decision 19). The protocol does not attempt to adjudicate death, verify heirs, or transfer soulbound certificates.

**How traditional equity handles death**: When a shareholder dies, the executor presents a death certificate and probate documents to the transfer agent. The transfer agent re-registers the *existing* shares in the beneficiary's name. Shares are never destroyed and never reissued — they are reassigned on the ledger. The company cannot reclaim them. The company does not issue new shares to replace the old ones. The shares themselves are unchanged; only the registered owner changes.

**The soulbound challenge**: With soulbound onchain certificates, there is no transfer agent ledger to update. The certificate IS the ledger. If the holder's wallet keys are available, the executor operates the wallet directly — this is the straightforward case. If keys are genuinely lost, the Stake is permanently inaccessible. Unlike traditional equity, there is no intermediary who can re-register ownership.

**Why we don't solve this at the protocol level**: Any on-chain inheritance mechanism requires answering "who decides someone is dead?" — a legal question, not a protocol question. Adding a death oracle or beneficiary designation creates attack surface (fraudulent death claims, social engineering) worse than the problem it solves. Attempting to mimic the transfer agent role at the smart contract level would reintroduce the centralized intermediary that the entire protocol is designed to eliminate.

**How it works in practice**:
1. **Keys available** (the expected case): Executor operates the wallet directly. Participates in governance, receives tokens post-transition, or burns Stakes per court order.
2. **Keys lost, pre-transition**: The authority can issue a compensating Claim→Stake to the beneficiary for the same units. The orphaned Stake inflates total outstanding. This is an imperfect solution — it creates phantom equity — but it's the same outcome as any permanently lost crypto asset.
3. **Keys lost, post-transition**: The orphaned Stake cannot be deposited in the vault. Those tokens are never minted and effectively don't exist. Governance can vote to issue compensating tokens to verified beneficiaries.

**The real solution is at the wallet layer**: Embedded wallets (see Decision 19) eliminate the key loss problem entirely. If holders authenticate through existing wallets, passkeys, or email — with no seed phrase to lose — then death/inheritance reduces to "does the executor have access to the holder's authentication methods?" This is the same problem as inheriting any online account, and it has well-understood solutions (password managers, estate planning tools, legal access to email).

**The inflation question**: If a holder dies and their Stake is permanently inaccessible, it inflates the outstanding share count. Is this acceptable? In practice, yes. The same thing happens with lost Bitcoin — approximately 4 million BTC are estimated permanently lost, and the market prices around it. Post-transition, orphaned Stakes reduce circulating supply (tokens that are never claimed), which is actually deflationary for remaining holders. Pre-transition, governance can account for known orphaned Stakes in dilution calculations.

**Counterpoints**:
- "Traditional equity never has this problem." — Correct. Traditional equity relies on centralized intermediaries (transfer agents, registrars) who can re-register ownership. This is the fundamental tradeoff of self-sovereign ownership: stronger property rights in exchange for stronger personal responsibility. The protocol chooses self-sovereignty and pushes recovery to the wallet/application layer.
- "Court orders could require share transfer to heirs." — The protocol can't transfer soulbound tokens. A court can order the estate to produce wallet keys, or the authority/governance can issue compensating equity to the heirs. The burn mechanism (Decision 5) also allows heirs with wallet access to surrender equity if needed.

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

---

## 19. Embedded Wallets as the Recommended Holder Interface

**Decision**: The protocol recommends that all Stake holders interact through embedded wallets — wallets authenticated via existing wallets, passkeys, or email rather than raw seed phrases. This is an application-layer recommendation, not a protocol-level enforcement.

**Rationale**: The single greatest risk to onchain equity holders is not smart contract bugs or governance attacks — it's key loss. A lost seed phrase means permanently inaccessible equity with no recovery path. This is fundamentally different from traditional equity, where a lost stock certificate can be replaced by the transfer agent.

Embedded wallets (Privy, Dynamic, Turnkey, Web3Auth, etc.) solve this by removing seed phrases entirely:
- **Authentication through existing credentials** — Holder connects with their existing wallet(s), email, or passkeys. No 12-word phrase to write down and lose.
- **Multi-signer support** — Multiple wallets or authentication methods can control the same embedded wallet. Losing one doesn't mean losing access.
- **Passkey support** — Biometric authentication (Face ID, fingerprint) as a wallet signer. Hardware-bound, phishing-resistant, and familiar to non-crypto users.
- **Recovery paths** — If a holder loses their primary auth method, backup methods (secondary wallet, email, passkey on another device) restore access.

**Why not enforce this at the protocol level**: The protocol is permissionless. Any Ethereum address can hold a Claim or Stake. Mandating a specific wallet type would compromise composability and censorship resistance. Instead, the applications built on the protocol (the cap table management tools, the onboarding flows) should default to embedded wallets and strongly discourage raw EOA usage for equity holding.

**How this resolves other risks**:
- **Key loss**: Eliminated by design — there are no keys to lose
- **Death/inheritance**: Reduces to "does the executor have access to the holder's email/device?" — a solved problem in estate law
- **Fraud via false key-loss claims**: If a holder claims they lost access but actually didn't, the embedded wallet provider's logs can verify whether the account was accessed. This is far more auditable than "I lost my seed phrase."

**Counterpoints**:
- "Embedded wallets introduce a centralized dependency." — The wallet provider is a convenience layer, not a custodian. The private key is still held by the user (via MPC, enclave, or passkey). If the provider disappears, the key can be exported. This is different from custodial solutions where the provider holds the key.
- "What if the embedded wallet provider is compromised?" — Same risk as any authentication provider. Mitigation: multi-signer setup where the embedded wallet is one of N signers. The protocol's soulbound property means a compromised wallet can't transfer Stakes to the attacker — the worst case is a burn (which is visible on-chain and auditable).
- "Crypto-native holders prefer their own wallets." — Fine. The protocol doesn't prevent this. But for the 99% of equity holders who are not crypto-native, embedded wallets are the right default.

---

## 20. Private Key Loss

**Decision**: If a holder loses access to their wallet and has no recovery path, their Stakes are permanently inaccessible. The protocol does not provide an override mechanism for the authority or board to recover or reissue Stakes on behalf of the holder.

**Rationale**: Any recovery mechanism that allows a third party (authority, board, admin) to reassign or reissue Stakes creates a backdoor that undermines the core property: irrevocability. If the authority can "recover" a lost Stake by issuing a new one and voiding the old one... wait, Stakes can't be voided. That's the point.

The temptation is to add a recovery function: "if the holder can prove they lost access, the authority reissues." But this creates an unfalsifiable claim problem — there is no cryptographic way to prove a private key is lost. The holder could be lying (to get double equity), or a social engineer could impersonate the holder. Any recovery mechanism based on identity verification reintroduces the trusted intermediary.

**Practical mitigation**:
1. **Embedded wallets** (Decision 19) eliminate seed phrase loss entirely
2. **Multi-signer wallets** provide redundancy — lose one key, recover via another
3. **Pre-transition**: Authority can issue a compensating Claim→Stake to the holder's new address, accepting the inflation of outstanding units as a cost of the error
4. **Post-transition**: Inaccessible Stakes don't receive tokens. The unclaimed tokens remain in the vault and can be redistributed by governance vote.

**The inflation tradeoff**: If the authority reissues a compensating Stake, total outstanding units increase. The orphaned Stake still exists — it just can't be used. This is equivalent to "phantom shares" — equity that exists on paper but has no active holder. In small quantities, this is manageable. In large quantities, it signals an operational problem (holders not using embedded wallets). The protocol accepts this tradeoff rather than compromising irrevocability.

**Counterpoints**:
- "Traditional equity doesn't have this problem." — Because traditional equity relies on centralized registrars who can re-register ownership. Every feature of centralized registrars that makes recovery possible also makes censorship and seizure possible. The protocol chooses censorship resistance over assisted recovery.
- "Could a dead man's switch help?" — A time-locked recovery mechanism (if no activity for X months, transfer to designated address) is interesting but dangerous. It creates a new attack vector: wait for the holder to go on vacation and claim their equity. It also contradicts soulbound — if there's a path to transfer under any condition, it's not truly soulbound. Better to solve this at the wallet layer.

---

## 21. Holder-Initiated Forfeiture (Burn)

**Decision**: Stake holders can burn (permanently destroy) their own Stakes at any time by calling `burn(stakeId)`. No approval from the authority, board, or any third party is required. The burn is irreversible.

**Rationale**: Traditional equity holders can surrender shares. This happens in practice:
- **Voluntary surrender** — Founder returns shares to simplify the cap table before a raise
- **Tax write-off** — Holder writes off worthless equity (Section 165 loss in US tax law)
- **Court-ordered forfeiture** — Court orders the holder to surrender shares; holder complies
- **Buyback completion** — Company pays the holder (off-chain), holder destroys the certificate
- **Estate cleanup** — Winding down a defunct company, clearing abandoned equity

Without burn, soulbound Stakes would accumulate forever — even after the company is dissolved, the equity is worthless, or a court has ordered forfeiture. Burn gives holders sovereignty over their own property, including the right to destroy it.

**Implementation**: `burn(stakeId)` checks `ownerOf(stakeId) == msg.sender`, cleans up storage (StakeState and pact mapping), and calls the ERC-721 internal `_burn`. This is the same pattern as ERC-20 burn functions (OpenZeppelin's ERC20Burnable), which are commonplace on Ethereum — nearly every major token supports holder-initiated burn.

**What burn is NOT**:
- Not revocation — the authority cannot burn someone else's Stake
- Not pausable — holder can burn even when the contract is paused
- Not restricted by transition — holder can burn pre-transition or post-transition
- Not conditional — no reason required, no approval needed

**How burn enables buyback without protocol-level mechanism**: The company negotiates a buyback off-chain (paying the holder in fiat, ETH, stablecoins, etc.). Once payment is confirmed, the holder burns their Stake. The protocol doesn't need to facilitate the payment — just the destruction. This is simpler, more flexible, and doesn't require the protocol to understand payment rails.

**Counterpoints**:
- "Can someone be coerced into burning?" — Yes, but coercion is a legal matter, not a protocol matter. Courts coerce people into surrendering property all the time (garnishment, forfeiture, divorce settlements). The protocol provides the mechanism; enforcement is legal.
- "What if a holder burns by mistake?" — Irreversible by design. The authority can issue a replacement Claim→Stake if the burn was accidental. This is no different from accidentally sending ETH to the wrong address — blockchain transactions are final.
- "Burning reduces outstanding units — does that affect other holders?" — Yes. Burning is equivalent to share cancellation/retirement. Remaining holders' percentage ownership increases slightly. This is expected and desirable in buyback scenarios.

---

## 22. Post-Transition Equity Issuance

**Decision**: After transition, new equity is issued as tokens via `governanceMint()` on StakeToken, not as soulbound certificates. Governance (GOVERNANCE_ROLE) can mint new tokens up to the `authorizedSupply` cap, and can raise that cap via `setAuthorizedSupply()`. This is the token-layer equivalent of the certificate-layer issuance pipeline.

**Rationale**: Public companies issue equity constantly — RSUs to new hires, secondary offerings to raise capital, stock splits, acquisition consideration. Freezing the certificate layer at transition (Decision 13) doesn't mean freezing all issuance — it means graduating issuance from the certificate system to the token system.

The two-step process mirrors traditional corporate governance:
1. **Authorize** — Governance raises `authorizedSupply` (equivalent to the board authorizing new shares, or shareholders approving an increase to authorized shares in the charter)
2. **Issue** — Governance calls `governanceMint(to, amount)` to mint tokens to a specific address (equivalent to the board approving a specific grant or offering)

Both steps require GOVERNANCE_ROLE, which is controlled by the post-transition governance mechanism (vault governance seats, token holder votes). No single individual can unilaterally mint.

**Why not continue using Claims and Stakes post-transition?**
- Claims and Stakes solve problems specific to private equity: vesting, revocation, soulbound ownership, conditional rights. Post-transition, equity is fungible and liquid. Vesting for public company employees is typically handled by the employer (company holds tokens in escrow, releases on schedule) or by standard token vesting contracts (Sablier, Hedgey). The heavyweight Claim machinery isn't needed.
- Continuing to use the certificate layer post-transition would require keeping the authority unfrozen, which undermines the trust guarantee of Decision 13.
- Token-based issuance is composable with the entire DeFi ecosystem — governance frameworks, vesting contracts, compensation platforms.

**The authorized supply cap**: `authorizedSupply` is set at token deployment and serves as the hard ceiling. `totalSupply()` can never exceed it. This is the on-chain equivalent of "authorized shares" in a corporate charter — the maximum the company can issue without a governance vote to raise it. Governance can increase it, but the increase itself is a governed action.

**Counterpoints**:
- "Governance could raise the cap to infinity and dilute everyone." — Same as IRL. A board could authorize billions of new shares. The protection is the governance mechanism itself — token holders who would be diluted can vote against it. The override mechanism in StakeVault provides an additional check: token holders can override governance decisions with a supermajority vote.
- "New hires won't get soulbound certificates, just tokens." — Correct. Post-transition, equity is fungible. If the company wants to restrict liquidity for new grants, they use standard token vesting contracts (time-locked escrow). The soulbound phase is over — the company has "gone public."
