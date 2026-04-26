# StartupFund — Smart Contracts

Six Solidity contracts powering the StartupFund decentralised crowdfunding dApp. Deployed via Remix IDE against a local Ganache development chain.

## Prerequisites

- Ganache desktop app — <https://trufflesuite.com/ganache/>
- MetaMask browser extension
- Chrome / Edge / Brave for Remix IDE
- The companion React repo (`../StartupFundApp`) running at `http://localhost:8080`

## Expected directory tree after unzip

```
StartupFund/
├── contracts/
│   ├── AccessControl.sol
│   ├── CampaignManager.sol
│   ├── CampaignVoting.sol
│   ├── FundingVault.sol
│   ├── ICampaign.sol
│   ├── IVerification.sol
│   ├── RewardToken.sol
│   └── StartupFund.sol
├── scripts/
│   ├── deploy-all.ts           ← the one-shot deploy script
│   ├── deploy_with_ethers.ts
│   └── ethers-lib.ts
├── tests/
├── HOW-TO-RUN.md
├── remix.config.json
└── README.md
```

If you see `__MACOSX/` or `.DS_Store` files after unzip, delete them:

```
rmdir /s /q __MACOSX
del /s /q .DS_Store
```

## 1. Ganache — create a new workspace

Open Ganache desktop.

1. Click **NEW WORKSPACE** → **Ethereum**.
2. **Workspace Name**: anything (e.g. `StartupFund-Dev`).
3. **Server** tab:
   - Hostname: `127.0.0.1`
   - Port Number: `7545`
   - Network ID / Chain ID: `1337`
4. **Accounts & Keys** tab: leave the 10-account default (each gets 100 ETH).
5. Click **Save Workspace** (top right). Ganache now shows the 10 accounts and begins mining.

## 2. MetaMask — add the network and import accounts

### Add the network

MetaMask → network dropdown → **Add network manually**:

| Field | Value |
|---|---|
| Network name | `Ganache Local` |
| RPC URL | `http://127.0.0.1:7545` |
| Chain ID | `1337` |
| Currency symbol | `ETH` |

Save → select the new network.

### Import accounts

In Ganache, each account row has a small key icon on the right — click it → copy the **private key** shown in the modal.

In MetaMask → click your account avatar → **Import account** → paste the private key → **Import**.

Repeat for at least three accounts so you can demonstrate creator, two contributors, and voter roles.

> ⚠️ These private keys are printed publicly by Ganache and must never be used on a real network. They are development-only.

## 3. Remix IDE — upload source

Open <https://remix.ethereum.org> in a new tab.

1. Click **File explorer** (2nd sidebar icon).
2. Drag the `contracts/` folder AND the `scripts/` folder from this repo onto the file explorer panel.

## 4. Compile — EVM version must be `paris`

1. Click **Solidity Compiler** (4th sidebar icon).
2. **Compiler version**: any `0.8.x` (e.g. `0.8.20`).
3. Expand **Advanced Configurations**.
4. **EVM Version** dropdown: change from its default to **`paris`**.
5. Click **Compile all**. Every `.sol` file should show a green checkmark.

### Why `paris`?

Ganache's EVM implementation does not support opcodes introduced after the Paris hardfork (for example the `MCOPY` opcode from Cancun). Compiling against a newer EVM target produces bytecode that fails with `invalid opcode` on first deploy. Paris is the most recent EVM version that Ganache can execute correctly.

## 5. Deploy — one-shot script

1. Click **Deploy & Run Transactions** (5th sidebar icon).
2. **Environment** dropdown: select **Injected Provider - MetaMask**.
3. MetaMask pops asking to connect → pick your deployer account (use the first imported Ganache account, which also becomes the contract owner).
4. Back in Remix, **File explorer** → right-click `scripts/deploy-all.ts` → **Run**.
5. MetaMask pops approximately thirteen times in sequence (6 contract deploys + 5 authorisations + 2 demo configuration calls). Click **Confirm** each time.
6. When the script finishes, the Remix console prints the complete TypeScript address block:

```
export const CONTRACT_ADDRESSES = {
  startupFund:     "0x...",
  campaignManager: "0x...",
  fundingVault:    "0x...",
  rewardToken:     "0x...",
  accessControl:   "0x...",
  campaignVoting:  "0x...",
};

export const CHAIN_ID = 1337;
```

## 6. Wire the frontend

Copy the block above and paste it over the contents of `../StartupFundApp/src/lib/contractAddresses.ts`. Save. If the React dev server is already running, Vite hot-reloads and the app begins reading the live chain.

## Contracts at a glance

| Contract | Responsibility |
|---|---|
| `AccessControl` | Wallet registration + block / pause controls |
| `CampaignManager` | Campaign records + status enum (PENDING, ACTIVE, FUNDED, CANCELLED, REJECTED) |
| `FundingVault` | ETH escrow per campaign — custody of contributions |
| `RewardToken` | ERC-20 token, 1:1 minted on successful campaigns |
| `CampaignVoting` | Community approval gate — configurable voting window + quorum |
| `StartupFund` | Orchestrator — sole entry point the frontend calls |

## Troubleshooting

| Symptom | Fix |
|---|---|
| Deploy fails with `invalid opcode` | EVM version is not `paris` — redo Step 4 |
| MetaMask shows wrong balance | Ganache was restarted — re-import account keys |
| Deploy script cannot find artifacts | Compile step never ran, or failed silently — check Solidity Compiler tab |
| Contracts deployed but frontend still shows mock data | Addresses were not pasted into `contractAddresses.ts` — redo Step 6 |
| MetaMask: `internal JSON-RPC error` on any tx | Ganache workspace closed or port conflict — confirm it is running on 127.0.0.1:7545 |

See `HOW-TO-RUN.md` for the extended walkthrough with screenshots and the manual-deploy fallback (skip `deploy-all.ts`, deploy each contract one at a time from the Remix deploy panel).
