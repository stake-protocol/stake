# stake
Stake Protocol spec, smart contracts, and SDK for non-transferable onchain ownership (Stakes &amp; Claims) plus Pact agreements and the private→public Transition.

Stake is a decentralized ownership system for crypto startups that replaces “token = equity” with non-transferable onchain ownership certificates.

Core primitives:
Stake: non-transferable ownership certificate (governance + distributions as configured).
Claim: non-transferable claim that can be redeemed into Stake (no governance until redeemed).
Pact: immutable onchain agreement defining terms between an issuer and counterparties (fundraising and other relationships).

Lifecycle:
Redeem: Claim → Stake.
Transition: private Stake/Claims → public tokenization event (optional; separate from Redeem).

Repo layout:
spec/ Protocol schemas and spec
contracts/ Smart contracts
sdk/ TypeScript SDK and types
app/ Commercial app (may be private or excluded)

Status: v0.x (schemas stabilizing).
