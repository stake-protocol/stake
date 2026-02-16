# Stake Protocol
## Bringing Startup Equity Onchain

Startup equity has not moved onchain. Traditional finance buried it under intermediaries, and crypto skipped it entirely.

Cap tables live in spreadsheets and centralized SaaS behind transfer agents, depositories, and custodians. Carta charges up to $112K/year for what amounts to a hosted database with a signature workflow[1]. The DTCC settles $3.7 quadrillion in securities annually through an intermediary stack designed in 1973[2]. A ten-person startup does not need a transfer agent, a depository, and a clearing firm. It needs a ledger everyone can see and no one can tamper with.

On the crypto side, true equity doesn't exist. Projects skip ownership entirely and jump straight to liquid tokens, even before they have users, revenue, or a product. Over 53% of the 25 million crypto tokens launched since 2021 are now dead, with 2025 alone accounting for 86% of total project failures[3]. The token economy has produced $2.4 trillion in market cap[4] but zero credible equity infrastructure.

The current workaround is a SAFE plus a token warrant, two instruments across two entities that don't know the other exists. This is a legal hack around the fact that crypto never built the thing it was supposed to replace.

Securitize and Fairmint tokenize equity into tradeable securities. MetaDAO, Street, Legion, and countless others are racing to bring equity onchain. But they all make ownership tradeable the moment it's issued. The missing piece is soulbound ownership. If equity can be sold before value is created, you get the same speculation cycle that killed 13.4 million tokens.

### Stake Protocol issues soulbound equity certificates onchain. It is the first decentralized protocol where ownership must be earned before it can be sold — the same principle that governed startup equity for four centuries, now enforced by smart contracts.

The protocol implements a deterministic lifecycle: Pact, Claim, Stake, Token.

A Pact, or Plain Agreement for Contract Terms, is an immutable onchain agreement that lets founders issue equity to themselves, their investors, employees, and contributors. When equity is issued under a Pact, the recipient gets a Claim — a contingent right, similar to an option, warrant or convertible, that vests over time according to the terms the founder set. Once a Claim is redeemed, it becomes a Stake — a soulbound ERC-721 certificate held directly in the owner's wallet that cannot be sold, traded, or listed.

Liquidity is not the default, it's the reward. When a project is ready, it can transition to an ERC-20 Token, unlocking public trading only after real value has been built. The initial public offering occurs through a Dutch auction lasting 3–7 days that discovers price the same way Google did in its 2004 IPO.

Every pathology of the token economy including pump-and-dump, governance attacks, founders dumping control, all trace back to premature liquidity. Soulbound certificates eliminate this at the protocol level.

Stake launches on Ethereum L1. Equity certificates are high-value, low-frequency instruments. A company issues a cap table once, not thousands of times per second. Issuing a full cap table of 50 certificates costs $15–60 on mainnet — trivial relative to the equity it represents. A certificate representing 10% of a $100 million company needs to live on a chain where the cost to attack exceeds the value at stake. Ethereum L1, secured by tens of billions in staked ETH, is the only credible settlement layer for that.

Pre-transition, the issuer controls the cap table the same way a real board operates. Post-transition, issuer powers freeze permanently. Governance transfers to a seat-based system where governors deposit certificates and commit for fixed terms, with staggered expiration ensuring continuity. Day-to-day governance requires skin in the game, not just token holdings. Token holders retain economic voting rights and emergency override capability, but governance requires commitment. Accountable governance, encoded in immutable contracts.

Stake Protocol does not charge issuers anything to issue certificates. Instead it charges a 1% fee on tokens minted at transition, collected once, in protocol-owned tokens, liquidated on a fixed schedule (90-day lockup, 12-month linear sell). No discretion, no insider selling, fully transparent onchain. The protocol is fully aligned with the success of its issuers and makes money only when projects succeed. For context, traditional IPO underwriters charge 4–7% of gross proceeds[9].

Because Stake is an open standard, anyone can build on top of it — exchanges for transitioned tokens, onchain cap table verifiers, portfolio dashboards for certificate holders, or governance tooling that plugs directly into the seat-based system.

The endgame is the Stake Market, a public exchange where every listing has an auditable onchain history from Pact through Token, with provenance enforced by smart contracts instead of committees. Stake is positioned to be the ERC-20 of equity, the standard that defines how ownership works onchain for the next four centuries.


Sources

[1] Carta pricing: Spendflo; Carta

[2] DTCC $100T in custody, $3.7 quadrillion annual settlement: DTCC Press Release, June 2025

[3] 10.7M dead tokens, 53% failure rate: CoinGecko; CoinDesk

[4] Total crypto market cap: CoinMarketCap

[5] IPO underwriting fees 4–7%: PwC
