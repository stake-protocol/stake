# Stake Protocol

## Onchain Equity for the Token Economy

**A Whitepaper — Draft v0.1**

---

## I. Abstract

Stake Protocol is an onchain system for issuing, managing, and optionally transitioning equity-like ownership stakes on Ethereum. It introduces the Stake Certificate: a non-transferable, wallet-held record that represents a real ownership position — not a speculative token, not a promise of future value, but an auditable, issuer-governed equity instrument.

The protocol models a deterministic lifecycle: **Pact, Claim, Stake, Token.** A Pact is the foundational agreement. A Claim is a contingent right. A Stake is confirmed ownership. A Token is optional — the liquidity layer that a project may or may not choose to add, on its own timeline, when it is ready.

This design separates ownership from speculation. Certificates are soulbound. They cannot be traded, airdropped to strangers, or listed on an exchange. They exist to represent what someone earned, invested, or was promised. When a project is ready to go public, the protocol provides a transition mechanism: certificates are deposited into a vault, tokens are minted, governance transfers from issuer control to a seat-based system, and the project enters the public market on its own terms.

Stake Protocol borrows four centuries of corporate governance — authorized shares, controlled issuance, anti-dilution protections, board elections — and encodes them in smart contracts on Ethereum L1. It does not reinvent equity. It puts equity onchain.

---

## II. The Problem

Equity infrastructure is broken in two directions.

**Traditional equity lives in the 1970s.** Cap tables are managed in spreadsheets, PDFs, and siloed SaaS platforms. Carta, the market leader, charges thousands per year for what amounts to a hosted database with a signature workflow. Ownership records pass through layers of intermediaries — transfer agents, depositories, broker-dealers, custodians — each extracting rent, each adding latency, each obscuring the direct relationship between a company and its owners. Settlement takes a business day. Cross-border ownership is a legal labyrinth. And for private companies, the entire system runs on trust: trust that the cap table is accurate, trust that the vesting schedule was honored, trust that the SAFE will convert at the terms agreed.

**Crypto equity doesn't exist.** Token-native projects skip equity entirely. They jump straight to liquid tokens — often before the project has users, revenue, or a product. The standard playbook: create a token with a fixed supply, allocate 20% to the team, 20% to investors, 30% to a "community treasury," 10% to an "ecosystem fund," and list on day one. This conflates ownership with speculation. Founders sell governance rights to strangers. Investors get liquid positions they can dump in months. The "community treasury" is a slush fund controlled by insiders. And the token price — not the product — becomes the measure of success.

The result: crypto projects lack the foundational ownership layer that every successful company in history has used. There is no credible way to say "this person owns 4% of this project" without it immediately becoming a tradeable, speculative asset.

**The gap is specific.** There is no onchain system that starts with equity — real, non-transferable, issuer-governed ownership — and optionally layers on liquidity later. Fairmint offers "continuous securities offerings" but runs on a centralized platform with a blockchain wrapper. Magna provides token vesting but doesn't solve the equity problem — it manages the distribution of tokens that already exist. Neither starts from the premise that ownership should be soulbound by default and liquid only by choice.

Stake Protocol fills this gap. It provides the equity infrastructure that crypto has been missing: a way to issue, manage, vest, revoke, and eventually tokenize ownership stakes — all onchain, all auditable, all without intermediaries.

---

## III. From Paper Certificates to Onchain Records

The history of equity ownership is a history of increasingly abstract representations of the same underlying reality: someone owns a piece of something. Each era solved one problem and created another.

### The Paper Era (1602–1973)

The first equity certificates were issued by the Dutch East India Company in 1602. They were physical documents — ink on paper — that entitled the bearer to a share of the company's profits. For nearly four centuries, this model persisted. The New York Stock Exchange, founded in 1792 under a buttonwood tree, was a marketplace for trading paper certificates. Settlement meant physically delivering certificates between parties. A purchase on Monday might settle by Thursday — if the courier didn't lose the paperwork.

By the 1960s, the system was collapsing under its own weight. Trading volume on the NYSE tripled between 1960 and 1967. Brokerages literally could not process the paper fast enough. The NYSE began closing on Wednesdays to catch up on settlement. In 1968, $400 million in securities went missing — not stolen, just lost in the shuffle of paper between desks. This was the Paperwork Crisis.

### The Intermediary Era (1973–Present)

The solution was the Depository Trust Company (DTC), established in 1973. DTC's innovation was simple: stop moving paper. Instead, immobilize certificates in a central vault and track ownership changes in a book-entry system. The physical certificate stayed in one place; only the ledger entries moved.

This worked. Settlement times dropped from T+5 to T+3, then T+2, then T+1. Volume scaled from millions to billions of daily transactions. But it created a new problem: layers.

Today, if you "own" shares of Apple through a brokerage account, the chain of custody looks like this: You have a claim on your broker. Your broker has a claim on its clearing firm. The clearing firm has a position at DTC. DTC's nominee (Cede & Co.) is the actual registered owner of the shares on Apple's books. You are the "beneficial owner" — a legal fiction that gives you economic rights without direct registration.

This intermediary stack introduces costs at every layer (custody fees, clearing fees, settlement fees), delays in every transfer (reconciliation between ledgers takes time even when each ledger is fast), opacity at every level (you cannot verify your ownership without trusting the chain of intermediaries), and counterparty risk at every node (the 2008 financial crisis demonstrated what happens when intermediaries fail). For public companies with liquid shares, this system works well enough. For private companies — startups, DAOs, early-stage projects — it is absurdly overbuilt. A ten-person startup does not need a transfer agent, a depository, and a clearing firm. It needs a ledger that everyone can see and no one can tamper with.

### The Onchain Era

Crypto's first attempt at onchain ownership — the ERC-20 token — was the equivalent of going back to bearer certificates. Whoever holds the token owns the asset. No registration, no identity, no restrictions. This solved the intermediary problem (tokens move peer-to-peer, instantly, globally) but reintroduced the problems that intermediaries were built to solve: no governance controls, no issuer oversight, no way to enforce vesting or revocation or transfer restrictions.

Stake Protocol represents a different path. It borrows from each era:

From the **paper era**: direct registered ownership. The certificate holder is the owner, recorded on the ledger, with no intermediary layers. The issuer knows exactly who holds what.

From the **intermediary era**: instant settlement, scalable record-keeping, and standardized interfaces. The blockchain is the ledger. Settlement is atomic — when a certificate is issued, ownership transfers in the same transaction. No reconciliation needed.

From **neither era**: programmable governance. Vesting schedules enforced by code. Revocation rules embedded in the agreement. Transfer restrictions that cannot be bypassed by a forged signature or a corrupt intermediary. And eventually, a transition to liquid tokens that inherits the full history and governance structure of the equity it replaces.

The result is a system where ownership is direct (no intermediaries), instant (blockchain settlement), auditable (all history onchain), programmable (vesting, revocation, governance in code), and optionally liquid (transition to tokens when ready). Four centuries of equity infrastructure, compressed into a smart contract.

---

## IV. Design Philosophy

Stake Protocol is built on five principles. Each is a deliberate choice with a deliberate tradeoff.

### Soulbound by Default

Certificates are non-transferable. A Stake certificate cannot be sold, traded, or transferred to another wallet. This is the single most important design decision in the protocol, and the one that will face the most resistance.

The case for soulboundness is simple: ownership should be earned before it is traded. A founder's equity represents years of work. An investor's stake represents a bet on a team. An employee's options represent a commitment to stay. None of these should be flippable on a DEX before the project has shipped a product.

Every pathology of the token economy — pump-and-dump schemes, governance attacks by mercenary capital, founders selling control to strangers — traces back to premature liquidity. Soulbound certificates eliminate premature liquidity at the protocol level. You cannot sell what cannot be transferred.

The tradeoff is real: illiquidity. Certificate holders cannot access the economic value of their ownership until the project transitions to tokens. For some holders, this is too restrictive. The protocol addresses this through the transition mechanism (Section VII), which provides a deliberate, governance-controlled path to liquidity. The key word is deliberate. Liquidity is a choice, not a default.

### Issuer Sovereignty

The issuer — the company, DAO, or protocol that creates the Pact — controls the cap table. The issuer can mint certificates, revoke unvested stakes, amend terms, and void certificates. This mirrors how real companies work. A startup's board controls the cap table. They decide who gets equity, how much, on what terms, and under what conditions it can be taken back.

This is a departure from crypto's ethos of permissionless, trustless systems. It is intentional. Early-stage equity requires trust. A founder who receives a four-year vesting grant trusts that the company will honor the schedule. An investor who signs a SAFE trusts that the conversion terms will be respected. Stake Protocol does not eliminate this trust — it makes it auditable. The Pact defines exactly what the issuer can and cannot do. The smart contract enforces it. If the issuer revokes a stake, the revocation is recorded onchain, permanently, with the reason hash. Trust, but verify.

Issuer sovereignty has a natural expiration date. At transition, issuer powers freeze. No more revocation, no more voiding, no more unilateral amendments. Governance transfers to the certificate-and-token-holder system described in Section VI. The issuer's absolute control is appropriate for a private company. It is inappropriate for a public one. The protocol enforces this distinction.

### Progressive Decentralization

Start centralized. End decentralized. This is how successful organizations actually evolve.

A formation-stage startup cannot operate as a DAO. It needs a founder (or small team) making fast decisions about who to hire, how to allocate equity, and when to change terms. The protocol supports this through issuer control. But as the project matures — raising money, hiring people, building a community — the governance structure should evolve. More stakeholders means more voices. The transition mechanism is the formalization of this evolution: centralized issuer control gives way to decentralized governance through certificates (governance seats) and tokens (economic voting).

The protocol does not force decentralization on a timeline. It provides the infrastructure for it and lets each project decide when.

### Equity First, Token Optional

The certificate IS the equity instrument. Tokens are an optional liquidity layer added later. Not the other way around.

This reverses the standard crypto approach, where the token comes first and equity is an afterthought (or a separate legal instrument entirely). In the standard crypto fundraising stack, a US startup raises money through a SAFE (equity) and simultaneously signs a Token Warrant (the right to purchase tokens at a nominal price when a TGE happens). Two documents. Two legal entities (a US C-Corp for the SAFE, a Cayman/BVI Token SPV for the warrant). Two systems tracking two different claims on two different forms of value.

A Stake certificate unifies these instruments. It represents both equity ownership AND the programmatic right to convert to tokens at transition. The certificate IS the SAFE and the warrant, collapsed into a single onchain primitive. When a project transitions, the certificate holder deposits their certificate and receives tokens — no separate warrant exercise, no entity shuffling, no legal document to dig up. The conversion right is embedded in the smart contract that issued the certificate.

### Four Hundred Years of Practice, Adapted Onchain

Stake Protocol does not invent a new model for corporate governance. It encodes the existing one.

Authorized shares? The token contract has a hard cap on authorized supply, changeable only by supermajority vote. Controlled issuance? Governance can issue new tokens up to 20% of outstanding supply annually without a general vote — mirroring the NYSE's 20% rule. Anti-dilution protections? Configurable per Pact, enforced by code. Board elections? Governance seats are auctioned annually, with term limits and forced rotation. Lockup periods? Configurable, with smart contract enforcement.

The argument is straightforward: equity markets have operated on controlled inflation for four centuries. Companies issue shares when they need capital, compensate employees with equity, and use stock as acquisition currency. This works because governance mechanisms control the rate of issuance. The crypto experiment of fixed-supply tokens was a reaction to fiat monetary inflation, not a principle of corporate governance. Bitcoin's fixed supply makes sense for a monetary asset. It makes no sense for a company's equity. A company needs to raise capital, hire people, and make acquisitions. Fixed supply prevents all three.

The innovation is not in the governance model. The innovation is in the enforcement mechanism. Traditional corporate governance relies on lawyers, courts, and regulators to enforce rules. Stake Protocol relies on smart contracts. The rules are the same. The enforcement is better.

---

## V. Protocol Architecture

### V.A. The Pact

A Pact is the foundational agreement that governs all certificates issued under it. It is the corporate charter, the stockholders' agreement, and the plan document, rolled into one content-addressed onchain record.

Every Pact has a deterministic identifier:

```
pact_id = keccak256(abi.encode(issuer_id, content_hash, keccak256(bytes(pact_version))))
```

The `content_hash` is computed from the canonical JSON representation of the Pact using RFC 8785 (JSON Canonicalization Scheme). This ensures that any two systems given the same Pact content will compute the same hash, regardless of JSON key ordering or whitespace differences.

A Pact defines:

- **Rights.** Three groups — Power (voting, veto, board seats, delegation), Priority (liquidation preference, dividends, conversion), and Protections (information rights, pro-rata, anti-dilution, lockup). Each right is a clause instance with an ID, enabled flag, and parameter hash.
- **Issuer powers.** What the issuer can do: revocation mode (none, unvested-only, per-stake flags), amendment mode (none, issuer-only, multisig threshold), amendment scope (future-only or retroactive if flagged).
- **Dispute resolution.** Governing law and venue, recorded onchain for evidentiary clarity.
- **Signing mode.** Whether the issuer's signature alone suffices or countersignature is required (offchain or onchain).

A Pact may be declared immutable, in which case no amendments, revocations, or voidings are possible for certificates issued under it. This is the strongest guarantee the protocol can offer: the terms are set in code and cannot be changed by anyone, including the issuer.

### V.B. The Claim

All certificate issuance starts as a Claim. This is a deliberate design choice.

A Claim is the universal issuance envelope. It unifies instruments that, in traditional finance, are tracked in different systems: SAFEs, stock option grants, restricted stock awards, milestone-based compensation, investor commitments pending conversion. The difference between these instruments is only in their conversion conditions. A SAFE converts on a funding event. An option converts on exercise. A milestone grant converts on achievement. All of them start as "you have been promised something, contingent on conditions."

By routing all issuance through Claims, the protocol achieves a single entry point for cap table records. There is no ambiguity about whether a promise has been formalized onchain — if it's a Claim, it's been recorded.

A Claim specifies:
- The Pact it was issued under (rights, rules, terms)
- The recipient's wallet address
- The maximum units claimable
- The conversion rule (immediate, timed, milestone, funding, eligibility)
- Unit type (shares, basis points, wei-denominated, or custom)
- Status flags (voided, revoked, redeemed, disputed)

Claims are soulbound. They cannot be transferred. They sit in the recipient's wallet as a visible, verifiable record of what they have been promised.

### V.C. The Stake

A Stake is a confirmed ownership position. It is created by converting (redeeming) a Claim when the conversion conditions are met.

The conversion is atomic: in a single transaction, the Claim is marked redeemed (terminal) and a new Stake certificate is minted to the same recipient. The Stake inherits the Pact reference from the Claim but carries its own properties:

- **Units.** The actual ownership amount (may be less than the Claim's maximum if partial conversion is used).
- **Vesting.** A hash of the vesting schedule payload (linear, cliff, monthly, custom), with start, cliff, and end timestamps.
- **Revocation.** A hash of the revocation conditions, subject to the Pact's revocation mode.

Stakes are soulbound. They cannot be transferred. They represent "this person owns this much of this project, under these terms." The chain carries a self-describing reference to everything needed to verify the ownership: what they own, under what agreement, with what vesting schedule, subject to what revocation rules.

### V.D. Non-Transferability

Certificates implement ERC-5192 (Minimal Soulbound NFTs). The soulbound property is enforced at the smart contract level: `transferFrom`, `safeTransferFrom`, `approve`, and `setApprovalForAll` all revert when a certificate is locked.

This is not a soft restriction. There is no "emergency unlock." There is no admin override that lets the issuer transfer someone's certificate to another wallet. The only state changes possible for a locked certificate are those defined in the Pact: vesting progression, revocation, voiding, and — at transition — unlocking and transfer to the vault.

The unlock mechanism exists exclusively for two events:
1. **Transition.** The issuer initiates a transition event, unlocking all certificates simultaneously and transferring them to the vault.
2. **Termination.** The issuer voids or revokes a certificate per Pact rules.

### V.E. Smart Contract Architecture

The protocol is implemented as a set of composable contracts on Ethereum L1:

- **StakePactRegistry.** Manages Pact creation, versioning, and lookup by `pact_id`. Enforces content-hash integrity and amendment rules.
- **SoulboundClaim.** ERC-721 contract for Claim certificates. Implements ERC-5192 soulbound semantics. Handles issuance, voiding, and the lock/unlock lifecycle.
- **SoulboundStake.** ERC-721 contract for Stake certificates. Implements ERC-5192 soulbound semantics. Handles conversion from Claims, vesting tracking, revocation, and voiding.
- **StakeCertificates.** The orchestrator contract that ties the system together. Manages the full lifecycle: Pact creation, Claim issuance, Claim-to-Stake conversion, revocation, voiding, and transition initiation.

Built on OpenZeppelin v5 (ERC721, AccessControl), Solidity 0.8.24+, deployed to Ethereum L1. The reference implementation prioritizes readability and auditability over gas optimization.

---

## VI. Governance Model

Governance in Stake Protocol has two distinct phases, separated by the transition event.

### VI.A. Pre-Transition: Issuer Control

Before transition, the issuer governs. This is not decentralized governance — it is explicit, auditable centralized control. The issuer creates Pacts, issues Claims, converts them to Stakes, revokes unvested positions, amends terms within Pact-defined rules, and voids certificates.

Certificate holders have rights defined in their Pact — voting weight, veto power, board seats, information access, pro-rata participation, anti-dilution protection. These rights are recorded onchain and enforceable under the Pact's governing law. But the day-to-day operation of the cap table is the issuer's responsibility.

Power and priority attributes — governance weight, liquidation preference, seniority ranking — are active during this phase. They define the internal hierarchy of ownership: who votes on what, who gets paid first in a liquidation, who has protective provisions.

This mirrors early-stage startup governance. Founders and investors control the board. The cap table is managed by the company. Decisions are fast and centralized because the organization is small and the trust relationships are direct.

### VI.B. Post-Transition: The Governance Simplification Event

Transition is a governance simplification event. The complex private-company structures — power classes, priority waterfalls, seniority tiers — collapse into a simple public system:

**Certificates are governance seats.** Each certificate held in the vault represents one governance seat. The governance weight of a seat equals the unit count on the certificate. A certificate representing 10,000 units carries more governance weight than one representing 1,000 units. This is analogous to weighted voting shares — the seat is the right to govern; the units are the power behind it.

**Term limits.** Every governance seat has a fixed term. The default is one year. At the end of a term, the seat returns to the vault and goes up for auction. No governor holds a seat indefinitely.

**Open auction for seats.** When a governance term expires, any token holder can bid for the seat. The bid is denominated in tokens. The minimum bid is 10% of the certificate's unit count in tokens — a floor that prevents trivially cheap governance capture. The highest bidder wins the seat.

**Certificates in the governor's wallet.** When a governor wins a seat, the certificate is transferred from the vault to their wallet. It is locked (soulbound) for the duration of the term — the governor cannot transfer it. But they hold it. It is visible in their wallet, usable as proof of governance authority, compatible with DAO tooling that reads ERC-721 ownership. At term end, the smart contract executes a forced transfer, returning the certificate to the vault. This is enforced by code — the governor cannot refuse to return the seat.

**Staggered terms.** Not all seats expire simultaneously. At transition, seats are assigned staggered expiration dates (e.g., for a 10-seat governance structure with 1-year terms, two seats expire every 2.4 months). This provides governance continuity — the entire board never turns over at once.

**Token holder override.** Token holders have one emergency power: replace all governors. This is the nuclear option, used when governance has failed — when governors are acting against the interests of the token holders they ostensibly serve. The threshold is 50%+1 of votes cast, with a minimum quorum of 20% of total token supply. If the vote passes, all current governors are removed, all seats return to the vault, and emergency auctions are held for every seat.

This is the crypto equivalent of a proxy fight. In traditional corporate governance, activist investors can rally shareholders to replace the board. The mechanism is the same; the execution is faster and more transparent.

### VI.C. Why This Model

The separation of governance instrument (certificate) from economic instrument (token) solves a problem that has plagued every token-governed protocol: the conflation of economic interest with governance authority.

When governance power is proportional to token holdings, governance is for sale. Anyone with enough capital can buy a controlling governance position, extract value, and sell. This is not theoretical — it has happened repeatedly in DeFi governance (Beanstalk, Build Finance, and numerous smaller protocols).

In Stake Protocol's model, governance requires commitment. You must bid tokens and lock them for a full term. You must hold the certificate in your wallet, publicly, for a year. Your governance authority is visible onchain for anyone to verify. And at the end of your term, you must compete again. Governance is not a passive consequence of holding tokens. It is an active, time-bound, publicly accountable commitment.

---

## VII. The Transition

### VII.A. What Transition Is

Transition is the optional, irreversible event where a certificate-based private structure becomes a token-based public one. It is the protocol's equivalent of an IPO.

Irreversibility is a feature. A company that has gone public cannot go private again by pressing a button. The transition to public markets is a one-way door that changes the governance structure, the ownership model, and the relationship between the organization and its stakeholders. Stake Protocol enforces this: once transition is initiated, issuer powers freeze permanently. No more unilateral revocation, no more voiding, no more amendment. The issuer becomes one participant among many in a governance system they no longer control.

### VII.B. The Vault

The vault is the smart contract that sits at the center of the post-transition system. It holds deposited certificates, manages the certificate-to-token relationship, and administers governance seat auctions.

At transition, all certificates are programmatically transferred to the vault in a single batch operation. For each certificate, the vault:
1. Records the certificate's metadata (units, vesting schedule, Pact reference)
2. Mints ERC-20 tokens proportional to the holder's vested units
3. Holds the tokens in escrow per the lockup schedule (default: 90 days for insiders)
4. Makes the tokens claimable by the original certificate holder after lockup

The batch operation is gas-efficient. Each certificate requires approximately 130,000 gas to process (unlock, transfer, mint tokens, update state). A 50-person cap table transitions in a single transaction for approximately 6.5 million gas — well within Ethereum's 30 million gas block limit. At current gas prices (1-3 gwei), this costs $15-60.

Post-transition, the vault serves three ongoing functions:
- **Governance seat custody.** Certificates not held by active governors reside in the vault, available for auction.
- **Governance seat auctions.** When terms expire, the vault administers the bidding process.
- **Forced reclaim.** At term end, the vault executes the forced transfer of certificates from governors' wallets back to the vault.

### VII.C. Price Discovery: The Dutch Auction

When a project transitions, new tokens are offered to the public through a Dutch auction — the same mechanism Google used for its 2004 IPO, specifically chosen to bypass Wall Street's intermediary-driven book-building process.

The auction works as follows:

The project sets an authorized token supply and designates 15-20% as the public offering tranche. The auction starts at a deliberately high price and decreases over a defined period (3-7 days). Participants place bids specifying how many tokens they want and the maximum price they will pay. When the auction concludes, all winning bidders pay the same clearing price — the lowest price at which all offered tokens are sold.

This produces a single, market-determined price. No underwriter sets the price. No roadshow allocates shares to favored institutions. No first-mover advantage rewards bots or whales. The market speaks, and the price is what the market says.

The Dutch auction replaces three of the five functions traditionally performed by an IPO underwriter:

| Underwriter Function | Dutch Auction Equivalent |
|---|---|
| Valuation | Prior funding rounds establish baseline; market determines final price |
| Price discovery | The auction mechanism itself |
| Capital commitment | Eliminated — tokens are sold directly to buyers, no intermediary bears inventory risk |
| Distribution | Direct purchase via smart contract — no allocation discretion |
| Post-listing stabilization | Protocol-owned liquidity (see below) |

### VII.D. Initial Liquidity

In a traditional IPO, the underwriter provides post-listing stabilization — buying shares if the price drops below the offering price. In crypto, there is no underwriter. The protocol must bootstrap its own liquidity.

The auction itself solves this. Participants deposit collateral (ETH or stablecoins) to buy tokens. This collateral accumulates in the auction contract. When the auction concludes, a portion of the proceeds is automatically paired with tokens from the liquidity allocation (3-5% of authorized supply) to seed a permanent Uniswap V3 or V4 liquidity pool.

This is protocol-owned liquidity. It is never withdrawn. The protocol earns trading fees from the position. The fees can be reinvested to deepen liquidity over time. Unlike liquidity mining programs that attract mercenary capital, protocol-owned liquidity is permanent — it does not flee when incentives decrease.

For projects requiring deeper markets, the protocol recommends engaging professional market makers using the standard loan-and-call-option model: the project loans tokens from the liquidity allocation to 2-3 market makers, who provide bid-ask spreads on exchanges. At term end (typically one year), the market maker returns the tokens or pays a pre-negotiated strike price.

### VII.E. Supply Architecture

The token supply follows the same authorized/issued/outstanding model used by every public company since the invention of the corporate charter.

**Authorized supply** is the hard cap set at transition. It can only be increased by a token holder supermajority vote (66%+ of votes cast, 25% quorum of total supply). This is the equivalent of a charter amendment — rare, deliberate, and requiring broad consensus.

**Issued supply** is what actually enters circulation at transition:

| Allocation | % of Authorized | Rationale |
|---|---|---|
| Existing stakeholders | 55-65% | 1:1 conversion from certificates. Vesting carries over. Subject to lockup. |
| Public offering | 15-20% | New tokens sold via Dutch auction. This is the dilution event. |
| Liquidity provision | 3-5% | Paired with auction proceeds to seed permanent DEX pool. |
| Contributor pool | 10-15% | Future employee/contributor compensation. 4-year vest, 1-year cliff. |
| Community | 2-5% | Retroactive rewards for genuine early users. Small, honest, capped. |

**Reserved (unissued) supply** remains authorized but unminted. Governance can deploy it for future capital raises, acquisitions, strategic partnerships, or expanded contributor compensation. Issuance up to 20% of outstanding supply annually requires only governance approval — mirroring the NYSE and NASDAQ 20% rule. Beyond 20%, a token holder vote is required.

What is deliberately absent from this model: no "treasury" allocation (companies do not IPO with 30% of their own stock in a vault they control), no "ecosystem fund" (a euphemism for discretionary insider spending), no "marketing" allocation (marketing is an operating expense, not an equity event), and no "advisor" allocation (advisors vest from the contributor pool like any other contributor).

### VII.F. The Lockup

Insider tokens are subject to a configurable lockup period after transition. The default is 90 days.

During lockup, tokens cannot be transferred or sold on open markets. They can, however, be used for two protocol-level functions:
- **Governance seat bids.** Locked tokens can be deposited to bid on governance seats. This is permitted because governance deposits do not create sell pressure — they remove tokens from circulation.
- **Token holder votes.** Locked tokens count toward the quorum and vote totals for token holder override votes.

The lockup exists to provide market stabilization during the price discovery period following transition. It is not a permanent restriction. After the lockup expires, all tokens are freely transferable.

Each project configures its own lockup parameters. The protocol provides the mechanism and the default. The project makes the choice.

### VII.G. Anti-Dilution Safeguards

Controlled issuance requires controls. The protocol provides five layers of protection against reckless dilution:

**The 20% rule.** Annual issuance beyond 20% of outstanding supply requires a token holder vote. This mirrors the NYSE and NASDAQ shareholder approval policies for significant share issuance.

**The authorized cap.** Total supply cannot exceed the authorized maximum. Increasing the cap requires a supermajority vote — a high bar that prevents casual expansion.

**Onchain transparency.** Every issuance event is recorded on Ethereum. There is no hidden dilution, no off-balance-sheet equity, no backroom deals that only surface in an annual report. Anyone can audit the supply in real time.

**The override.** Token holders who believe governance is diluting recklessly can invoke the emergency override (50%+1 votes, 20% quorum) to replace all governors. This is the ultimate check — the governed can replace the governors.

**Optional preemptive rights.** Projects can enable preemptive rights, giving existing token holders the first right to purchase new issuance at the offering price, proportional to their current holdings. This prevents dilution of ownership percentage for holders who want to maintain their position.

---

## VIII. Why Controlled Inflation, Not Fixed Supply

The crypto industry's default tokenomics model — mint the entire supply at launch, then create artificial scarcity through burns and locks — is a solution to a problem that equity does not have.

Bitcoin's fixed supply of 21 million makes sense. Bitcoin is a monetary asset. Its value proposition is scarcity. Increasing the supply would undermine the fundamental thesis.

A company's equity is not a monetary asset. Its value comes from the company's ability to grow, raise capital, hire talent, and make acquisitions. All of these require the ability to issue new equity. A company with fixed-supply equity cannot:

- **Raise capital.** No new shares to sell to investors.
- **Compensate employees.** No equity grants, no stock options, no RSUs.
- **Make acquisitions.** No stock-for-stock deals.
- **Adapt to changing circumstances.** No ability to restructure, recapitalize, or raise emergency funding.

Four hundred years of corporate governance have converged on a model: authorized supply with governance-controlled issuance. The authorization sets the ceiling. Governance decides when and how much to issue within that ceiling. Shareholders (token holders) have oversight mechanisms to prevent abuse.

The crypto industry's departure from this model was not a principled innovation. It was a regulatory workaround. Projects issued 100% of supply at launch because it simplified the legal analysis — if all tokens exist from day one, there is no ongoing "issuance" that might constitute a securities offering. The result was economically incoherent: projects sitting on treasuries of their own tokens (imagine Apple holding 30% of its own shares in a vault), "ecosystem funds" that function as unaccountable slush funds, and elaborate vesting/unlock schedules that create predictable sell pressure at known dates.

Stake Protocol adopts the time-tested model. Authorized supply with a hard cap. Governance-controlled issuance. Anti-dilution protections. The difference from traditional equity is not the model — it is the enforcement. The controls are transparent, programmatic, and enforced by code on Ethereum, not by regulators, lawyers, or courts.

---

## IX. Acquisitions

Ownership infrastructure must support the full lifecycle of a company, including its end. Acquisitions are the most common path to exit for startups.

### Pre-Transition Acquisitions

When both the acquirer and target are still in the certificate phase, acquisition is necessarily friendly. Soulbound certificates cannot be purchased on an open market. There is no hostile takeover mechanism — which mirrors reality, as hostile takeovers of private companies are virtually impossible in the traditional world as well.

The process: the acquirer and target's governance agree on terms. The target's issuer initiates a dissolution event. All certificates are voided, and consideration is distributed to holders based on their units. Consideration can be the acquirer's certificates (a stock-for-stock deal, where the target's holders become stakeholders in the acquiring entity), stablecoins or ETH (a cash deal), or a combination.

### Post-Transition Acquisitions

After transition, three acquisition paths exist:

**Friendly merger.** Both governance bodies agree on terms. Certificate holders (governors) of both entities vote to approve. Token holders of the target vote to ratify. A smart contract executes the exchange: target tokens become redeemable for acquirer tokens (or ETH/stablecoins) at the agreed ratio. The target's vault dissolves, governance certificates are voided, and the target ceases to exist as an independent protocol.

**Tender offer.** The acquirer offers to buy target tokens directly from holders at a premium. If the acquirer accumulates more than 50% of the target's token supply, they can invoke the token holder override to replace all of the target's governors, effectively gaining control.

**Governance seat accumulation.** The acquirer bids on the target's governance seats at auction over multiple term cycles, gradually gaining majority control. Slower and less expensive than a tender offer, but requires patience and ongoing capital commitment.

---

## X. Ethereum L1 Deployment

Stake Protocol deploys to Ethereum L1. Not an L2. Not a sidechain. Not an app-specific chain.

The rationale is specific to what equity certificates require:

**Permanence.** An equity certificate may need to be verifiable in ten years. Twenty years. Ethereum L1 has the strongest guarantee of any blockchain that it will still be running, with the same state, decades from now. L2s are younger, less battle-tested, and dependent on L1 for security. For a document that might outlive the team that created it, permanence is not optional.

**Security budget.** Ethereum L1 is secured by billions of dollars in staked ETH. The cost to attack the network — to rewrite history, to forge a certificate, to alter a cap table — is prohibitively high. This matters for equity. A certificate that represents 10% of a company worth $100 million must be secured by a system whose attack cost exceeds the value at stake.

**Credible neutrality.** No single entity controls Ethereum L1. No foundation can freeze assets, no multisig can pause the chain, no governance vote can censor transactions. This matters for equity that may involve disputes between issuers and holders. Neither party can pressure the infrastructure layer.

**Composability.** Ethereum L1 is where the governance tooling lives (Tally, Snapshot, Governor contracts), where the identity systems live (ENS, attestations), and where the DeFi infrastructure lives (Uniswap, Aave, Compound) that post-transition tokens need to interact with.

**Cost is acceptable.** At current gas prices (0.5-3 gwei), the cost of operating a 50-person cap table on Ethereum L1 is approximately $27-53 for the full set of certificate operations (pact creation, claim issuance, stake conversion). A transition event for the same cap table costs $15-60. These are one-time or infrequent costs for high-value operations. Equity events happen monthly at most, not per-second.

---

## XI. Security Considerations

### Issuer Key Management

The issuer's authority address controls the cap table. Compromise of this key means unauthorized issuance, revocation, or voiding of certificates. Production deployments should use a multisig wallet (Gnosis Safe or equivalent) with a threshold appropriate to the organization's size. The reference implementation uses a single address for simplicity; this is explicitly not recommended for production.

### Certificate Integrity

Each certificate references a Pact by its content-addressed `pact_id`. The Pact's `content_hash` is computed using RFC 8785 (JSON Canonicalization Scheme) and keccak256. This ensures that the onchain record unambiguously points to a specific version of a specific agreement. Altering the Pact content would produce a different hash, detectable by any verifier.

### Soulbound Guarantees

The non-transferability of certificates is enforced at the smart contract level. All transfer functions (`transferFrom`, `safeTransferFrom`) revert for locked tokens. Approval functions (`approve`, `setApprovalForAll`) also revert, preventing any transfer-adjacent flows. The only entity that can move a locked certificate is the contract itself, during protocol-defined events (transition, revocation, governance reclaim).

### Transition Irreversibility

Once `initiateTransition()` is called, the process cannot be reversed. All certificates are transferred to the vault, tokens are minted, and issuer powers are frozen in a single atomic sequence. There is no "undo" function. This is by design — the transition to public markets is a permanent structural change.

### Governance Attack Vectors

Post-transition governance faces several attack vectors, each with mitigations:

- **Governance capture via auction.** An attacker bids on all governance seats. Mitigated by: minimum bid floors (10% of cert units), term limits (seats rotate, attack must be sustained), and token holder override (if captured governors act against holders, they can be replaced).
- **Token holder override abuse.** A whale with 50%+ voting power force-replaces governors. Mitigated by: 20% quorum requirement (the whale needs broad participation, not just their own votes), and the cost of acquiring 50% of supply.
- **Flash loan governance attacks.** Borrowing tokens to vote. Mitigated by: governance seat bidding requires token deposit (not just holding), and term-length lockup makes flash loans impractical.

---

## XII. Comparison to Existing Approaches

### vs. Traditional Equity Platforms (Carta, Pulley, AngelList)

Traditional platforms are databases with legal workflows. They track cap tables in centralized systems, generate legal documents, and manage compliance. They are effective for what they do, but they are intermediaries. The cap table lives on Carta's servers, not on a ledger the company and its stakeholders can independently verify. If Carta shuts down, goes bankrupt, or changes its pricing, the company must migrate. Stake Protocol puts the cap table on Ethereum — a ledger that requires no intermediary, no subscription, and no permission to read.

### vs. Token-First Approaches (Standard ERC-20 Launches)

Token-first approaches skip the equity step. They go directly to liquid, tradeable tokens — conflating ownership with speculation from day one. This works for protocols that are genuinely decentralized from launch (no identifiable team, no investors, no vesting). For projects with founders, investors, and employees — which is most projects — it creates a mismatch between the ownership structure (concentrated, with vesting) and the token structure (liquid, freely tradeable). Stake Protocol starts with the ownership structure and adds liquidity only when the project is ready.

### vs. Hybrid Platforms (Fairmint, Magna)

Fairmint offers continuous securities offerings with a "Rolling SAFE" model, but runs on a centralized platform. The blockchain component is secondary to the platform itself. Magna provides token management (vesting, distribution, claims) but operates on tokens that already exist — it does not solve the equity representation problem. Both are closer to "blockchain-enhanced SaaS" than to onchain-native infrastructure. Stake Protocol is a smart contract standard, not a platform. Any application can build on it. No platform dependency.

### vs. DAO Tooling (Aragon, Tally, Snapshot)

DAO tools provide governance mechanisms for token-holding communities. They are valuable infrastructure. But they assume the token already exists and is freely tradeable. They do not address the pre-token phase — the period where a project has founders, investors, and employees with vesting schedules, but no liquid token. Stake Protocol covers this entire phase and provides the bridge to the token phase when the project is ready.

---

## XIII. Future Work

The protocol's architecture is designed to support extensions without modification to the core certificate standard. Several directions are under consideration:

**Secondary markets for post-transition tokens.** Infrastructure for trading tokens that emerge from the transition process, potentially including order matching, price discovery, and liquidity aggregation.

**Cross-protocol acquisition infrastructure.** Standardized smart contracts for executing mergers and acquisitions between Stake Protocol-based entities, including atomic swaps of certificates and tokens.

**Governance tooling integration.** Deeper integration with existing governance frameworks (Tally, Snapshot, OpenZeppelin Governor) to make certificate-based governance accessible through familiar interfaces.

**Legal compliance frameworks.** Optional modules for jurisdictional compliance — KYC/AML attestations, accredited investor verification, transfer restrictions by geography — that can be layered on top of the core protocol without modifying it.

**Multi-chain considerations.** While Ethereum L1 is the canonical deployment for its permanence and security guarantees, the certificate standard may be implemented on other EVM-compatible chains for specific use cases where different cost and performance tradeoffs are appropriate.

---

## XIV. References

1. ERC-721: Non-Fungible Token Standard. W. Entriken, D. Shirley, J. Evans, N. Sachs. https://eips.ethereum.org/EIPS/eip-721
2. ERC-5192: Minimal Soulbound NFTs. T. Sterner, H. Rook. https://eips.ethereum.org/EIPS/eip-5192
3. ERC-165: Standard Interface Detection. C. Burgess, N. Johnson, F. Giordano. https://eips.ethereum.org/EIPS/eip-165
4. RFC 8785: JSON Canonicalization Scheme (JCS). A. Rundgren, B. Jordan, S. Erdtman. https://datatracker.ietf.org/doc/html/rfc8785
5. NYSE Listed Company Manual, Section 312.03: Shareholder Approval Policy.
6. Delaware General Corporation Law, Sections 151-157: Issuance of Stock.
7. Google Inc. S-1 Registration Statement, 2004. Dutch auction IPO precedent.
8. Vitalik Buterin. "Soulbound." January 2022. https://vitalik.eth.limo/general/2022/01/26/soulbound.html
9. E. Glen Weyl, Puja Ohlhaver, Vitalik Buterin. "Decentralized Society: Finding Web3's Soul." May 2022.

---

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
