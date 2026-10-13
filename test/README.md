# BIC token tests

Run `forge build` and `forge test` from the repository root. The suite uses the
existing vendored dependencies and needs no network, fork, environment variables,
or private keys.

- `BICToken.t.sol` retains the original deployment, metadata, mint-event, transfer,
  approval, failure-path, launch-distribution, and privileged-selector checks.
- `BICToken.edges.t.sol` adds boundary and authorization cases, including one minor
  unit, exhausted approvals, the largest finite approval, infinite-approval
  replacement, self-transfers, caller versus transaction-origin authorization,
  and state preservation on failure. Six additional fuzz properties run 1,000
  examples each. Round trips and splitting a transfer check for value loss or
  creation without reproducing the token's internal implementation.
- `BICToken.invariant.t.sol` runs 256 sequences of 128 handler calls. The handler
  mixes transfers, approvals, delegated spending, full-balance movements, and
  expected failures across five actors. Dedicated funded actions ensure the
  campaign exercises nonzero transfers and delegated spending even when the
  supply becomes concentrated in one holder.

The invariant ledger starts from the specified constructor supply and records
requested incoming/outgoing transfers and approvals. It never repairs its
expectations using token getters. After each handler call, the properties check:

1. Supply and metadata remain fixed, and all supply remains with the tracked actors.
2. Each actor's balance equals its initial allocation plus receipts minus spending.
3. Every owner/spender allowance matches approvals and successful delegated spending,
   including infinite approvals and rollback on rejection.

Expected failures use exact custom errors; unexpected reverts fail the campaign.
After each sequence, every actor must still be able to transfer its entire balance.
Only the explicitly selected handler methods are fuzz targets. Token state is
changed exclusively through its public interface.

The five-actor model is a closed accounting domain, not an exhaustive enumeration
of all addresses or all possible call sequences. The zero-caller unit test uses
`prank` to exercise defensive checks; it does not represent a transaction that an
ordinary account can originate. Launch-distribution tests check token movements;
the separate supplied protected harness owns the actual factory/AMM integration.
