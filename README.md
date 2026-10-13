# Bankers In Control (BIC)

An immutable ERC-20 with a fixed supply, implemented in `src/BICToken.sol` using the vendored OpenZeppelin Contracts v5.0.2 ERC-20 implementation.

| Deployment parameter | Value |
| --- | --- |
| Solidity contract | `BICToken` |
| Token name | `Bankers In Control` |
| Symbol | `BIC` |
| Decimals | `18` |
| Human-readable supply | `1,000,000,000 BIC` |
| Base-unit supply | `1000000000000000000000000000` (10^27) |
| Constructor arguments | None |
| Initial recipient | Constructor `msg.sender` (the deployer) |
| Launch chain | Ethereum, chain ID 1 |

The constructor mints the entire supply once and emits `Transfer(address(0), deployer, supply)`. When a factory deploys the token, the factory receives the entire supply. The token never uses `tx.origin` or makes an external call in its constructor. Deploy the concrete contract directly, not through a proxy; no initialization transaction is needed.

## Behavior and assumptions

The brief specifies no additional transfer rules, so BIC uses standard ERC-20 transfers and approvals. Transfers deliver their exact amount: there are no taxes, fees, rebases, locks, or address exemptions. Zero-value transfers between valid addresses succeed and emit a `Transfer` event. Transfers to the zero address revert, including zero-value transfers. Approvals to the zero address revert.

`transferFrom` requires sufficient allowance and balance. Finite allowances decrease when spent. An allowance of `type(uint256).max` follows OpenZeppelin's unlimited-approval convention and is not decreased. `approve` replaces the current allowance, and approving zero revokes it. Following OpenZeppelin v5 behavior, spending an allowance does not emit another `Approval` event. Off-chain consumers should query `allowance` rather than reconstruct it solely from events.

There is no owner, administrator, privileged balance control, external mint/burn function, pause, blacklist, seizure, upgrade, or permit extension. The deployer has only the rights of an ordinary holder after construction. Total supply remains exactly 10^27 base units for the lifetime of this deployed contract. The inherited mint/burn helpers are internal and have no callable entry point after construction.

## Build and checks

Install Foundry with Solidity 0.8.26 available, then run from this repository root:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26 and Cancun, enables the optimizer with 200 runs, and sets `bytecode_hash = "none"`. The launch chain must support Cancun. No FFI, filesystem permissions, environment variables, fork RPC, or network dependencies are needed by the tests. Both library dependencies are ordinary files in `lib/`; their version, archive checksum, and licenses are recorded there. The compiler and Foundry are tooling prerequisites, not vendored dependencies.

The tests cover constructor mint and event, metadata, factory deployment, full/zero/self transfers, exact delivery, approvals and revocation, finite/infinite allowances, allowance exhaustion, unauthorized spending, invalid addresses, insufficient balances, atomic rollback, absence of administrative entry points, and forbidden runtime opcodes. Four fuzz tests cover valid and invalid amounts with 1,000 cases each. A stateful invariant test runs 256 sequences of 64 transfers/approvals/delegated transfers among five actors and checks supply and balance conservation. Tests use independent deployments and no shared environment configuration.

The local distribution test models exact 10% distributor, 80% pool, and 10% remainder transfers, followed by a contributor claim. It does not deploy a Uniswap pool or claim to reproduce the supplied protected launch harness: that harness requires launch inputs supplied by the independent verifier. The token has no special pool logic and treats the factory, distributor, pool manager, and traders like any other addresses.

## Deployment and operational responsibilities

The launch operator deploys `BICToken` from its compiled creation bytecode with an empty constructor-argument list, and confirms the name, symbol, decimals, supply, constructor event, and initial deployer balance. Deployment through the launch factory correctly mints everything to that factory. The operator handles the launch manifest, supply distribution, liquidity creation, deployment address recording, and explorer source verification; this repository does not broadcast transactions or supply a manifest.

The assignment's factory launch policy allocates 10% to the contributor distributor, 80% to the liquidity pool, and the remaining 10% to the requester. Those allocations are executed by the launch system after construction; the token itself reserves or transfers nothing during deployment. Pool settings and launch economics belong to that system and are not constructor arguments.

### After launch

No configuration setters, service accounts, or ongoing keeper tasks are required. Holders are responsible for wallet custody, checking recipient addresses and base-unit amounts, and granting allowances only to trusted spenders. Prefer bounded allowances; when replacing an existing nonzero allowance, revoke it first and wait for confirmation before granting the new amount to reduce the standard ERC-20 allowance replacement race. Anyone with a granted allowance may spend it according to the ERC-20 rules.

Tokens transferred to this contract or another address without a withdrawal mechanism may become inaccessible: BIC has no rescue authority. Accidental transfers cannot be reversed administratively. Deployment custodians must safely distribute the initial supply; there is no recovery or upgrade mechanism if they lose access. Ordinary native-ETH transfers are unsupported.

The work includes Foundry unit, fuzz, and invariant checks and a manual review against the supplied security reference. No Slither/Mythril analysis or independent security audit is claimed. Production release review and post-deployment verification remain the launch operator's responsibilities.
