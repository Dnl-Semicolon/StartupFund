# StartupFund — Deploy & Test Guide

This guide walks you through deploying the smart contracts and testing the full user flow, including the **new community voting gate** that every campaign must pass before going live. Written for teammates who may be new to Remix IDE and Ganache.

**You need four things open at the same time:**
| Tool | What it does |
|------|-------------|
| **Ganache** | Runs a fake local Ethereum blockchain with 10 test accounts |
| **MetaMask** | Chrome extension — your wallet. Connects to Ganache. |
| **Remix IDE** | Browser-based IDE at https://remix.ethereum.org — compile + deploy contracts |
| **Chrome** | Runs the React frontend at http://localhost:8080 |

> **What changed in this deploy?** The platform now has a **CampaignVoting** contract. New campaigns enter a PENDING state and must be approved by community vote before they can accept contributions. You'll deploy 6 contracts (was 5) and run 4 authorization calls (was 3). There's also a demo shortcut to shrink the voting window so the class demo isn't blocked on 72-hour waits.

---

## Step 0 — Connect MetaMask to Ganache (do this once)

Skip this step if MetaMask already shows the "Ganache" network in its network dropdown.

1. Open MetaMask in Chrome (click the fox extension icon)
2. Click the network selector at the top (shows "Ethereum Mainnet" by default)
3. Click **"Add a network"** → **"Add a network manually"**
4. Fill in exactly:
   - Network name: `Ganache`
   - RPC URL: `http://127.0.0.1:7545`
   - Chain ID: `1337`
   - Currency symbol: `ETH`
5. Click **Save** → select the Ganache network

**Import three Ganache accounts into MetaMask (you need three to test voting + funding):**

1. In Ganache, click the key icon 🔑 next to Account 1 → copy the private key
2. In MetaMask → click your account icon (top right) → **"Import Account"** → paste the private key → click Import
3. Repeat for Account 2 and Account 3

> **Why three?** Account 1 = campaign creator. Accounts 2 and 3 = voters who approve the campaign so it can go ACTIVE. One of them will also fund it.

---

## Step 1 — Load contract files into Remix

1. Go to https://remix.ethereum.org
2. Click **File Explorer** (sidebar icon 2 — overlapping pages)
3. Click the **"Upload files"** button (or drag and drop every file from `/Users/danieltan/StartupFund/contracts/` into the file explorer panel)

Upload all eight files:
- `ICampaign.sol`
- `IVerification.sol`
- `AccessControl.sol`
- `RewardToken.sol`
- `CampaignManager.sol`
- `FundingVault.sol`
- `CampaignVoting.sol`  **← new**
- `StartupFund.sol`

**Tip:** Dragging the entire `contracts/` folder onto the Remix file explorer uploads everything at once.

---

## Step 2 — Connect Remix to Ganache via MetaMask

1. Click **Deploy & Run Transactions** (sidebar icon 5 — Ethereum diamond)
2. Change the **"Environment"** dropdown from "Remix VM" to **"Injected Provider - MetaMask"**
3. MetaMask will pop up asking to connect → click **Connect**
4. Confirm the account shown in Remix matches one of your Ganache accounts
5. You should see your Ganache ETH balance (100 ETH) in Remix

---

## Step 3 — Compile all contracts

**This is the most important step. EVM version must be set to Paris.**

1. Click **Solidity Compiler** (sidebar icon 4 — diamond/Solidity icon)
2. Set the compiler version to **0.8.x** (any version starting with 0.8, e.g. 0.8.20)
3. Scroll down to **"Advanced Configurations"** — click it to expand
4. Find the **"EVM Version"** dropdown — it defaults to "prague". **Change it to "paris"**
5. Click **"Compile All"** (or compile each `.sol` file individually using Ctrl+S / Cmd+S while the file is open)

✅ Green checkmarks on each file = success. Fix red errors before moving on.

> **Why Paris?** The Ganache blockchain version we're using doesn't support opcodes introduced after the Paris hardfork. Using a newer EVM version (like Prague) will produce bytecode that fails to deploy.

> **OpenZeppelin note:** When compiling `RewardToken.sol`, Remix will automatically download `@openzeppelin/contracts` from npm. This requires an internet connection and may take a few seconds the first time.

---

## Step 4 — Deploy contracts (do these in order)

Make sure you're on the **Deploy & Run Transactions** tab (sidebar icon 5) and MetaMask is connected (Step 2). Use **Account 1** as the deployer for every step — this makes Account 1 the owner of every contract, which matters in Step 5.

For each deployment: select the contract from the dropdown, click Deploy, confirm in MetaMask, then copy the deployed address from the "Deployed Contracts" section at the bottom of the panel.

### 4a — Deploy AccessControl
1. Select `AccessControl` in the contract dropdown
2. Click **Deploy** → MetaMask pops up → **Confirm**
3. Copy address → save as `AC_ADDR`

### 4b — Deploy CampaignManager
1. Select `CampaignManager`
2. Click **Deploy** → Confirm
3. Copy address → save as `CM_ADDR`

### 4c — Deploy FundingVault
1. Select `FundingVault`
2. Click **Deploy** → Confirm
3. Copy address → save as `FV_ADDR`

### 4d — Deploy RewardToken
1. Select `RewardToken`
2. Click **Deploy** → Confirm
3. Copy address → save as `RT_ADDR`

### 4e — Deploy CampaignVoting (takes 2 addresses)
1. Select `CampaignVoting`
2. Two input boxes appear. Paste:
   - `_campaignManager`: paste `CM_ADDR`
   - `_accessControl`: paste `AC_ADDR`
3. Click **Deploy** → Confirm
4. Copy address → save as `CV_ADDR`

### 4f — Deploy StartupFund (main contract — takes all 5 addresses)
1. Select `StartupFund`
2. Five input boxes appear. Paste:
   - `_campaignManager`: paste `CM_ADDR`
   - `_fundingVault`:    paste `FV_ADDR`
   - `_rewardToken`:     paste `RT_ADDR`
   - `_accessControl`:   paste `AC_ADDR`
   - `_campaignVoting`:  paste `CV_ADDR`
3. Click **Deploy** → Confirm in MetaMask
4. Copy address → save as `SF_ADDR`

---

## Step 5 — Authorize contracts to talk to each other

**Do not skip this step.** StartupFund needs permission to call the other contracts, and CampaignVoting needs permission to flip campaigns from PENDING to ACTIVE. Run all four authorization calls using **Account 1** (the deployer — same account you used in Step 4).

### 5a — Authorize StartupFund in RewardToken
1. In "Deployed Contracts", expand **RewardToken**
2. Find `setMinter`
3. Paste `SF_ADDR` → click `setMinter` → Confirm

### 5b — Authorize StartupFund in CampaignManager
1. Expand **CampaignManager**
2. Find `setAuthorized`
3. Paste `SF_ADDR` → click → Confirm

### 5c — Authorize StartupFund in FundingVault
1. Expand **FundingVault**
2. Find `setAuthorized`
3. Paste `SF_ADDR` → click → Confirm

### 5d — Authorize CampaignVoting in CampaignManager
1. Expand **CampaignManager**
2. Find `setVotingContract`
3. Paste `CV_ADDR` → click → Confirm

### 5e — Authorize StartupFund in CampaignVoting
1. Expand **CampaignVoting**
2. Find `setAuthorized`
3. Paste `SF_ADDR` → click → Confirm

✅ **Contracts are now fully wired.**

---

## Step 6 — (Demo only) Shrink the voting window

The contract's real-world default is a 72-hour voting window with 10-vote quorum. For a class demo that's impractical — use this shortcut to make voting settle in 2 minutes with only 2 votes.

**Do this step using Account 1 (the deployer).** These functions are `onlyOwner`.

### 6a — Shorten the window to 2 minutes
1. Expand **CampaignVoting**
2. Find `setVotingWindow`
3. Enter `120` (seconds) → click → Confirm

### 6b — Lower the quorum to 2 votes
1. In the same CampaignVoting panel, find `setQuorum`
2. Enter `2` → click → Confirm

> **What to say during the demo:** "We've set the quorum to 2 and window to 2 minutes here purely for demo timing. In production these defaults are 10 votes and 72 hours — visible in the contract source."

---

## Step 7 — Update the frontend with deployed addresses

Open `/Users/danieltan/StartupFundApp/src/lib/contractAddresses.ts` and replace every placeholder:

```typescript
export const CONTRACT_ADDRESSES = {
  startupFund:     "SF_ADDR",
  campaignManager: "CM_ADDR",
  fundingVault:    "FV_ADDR",
  rewardToken:     "RT_ADDR",
  accessControl:   "AC_ADDR",
  campaignVoting:  "CV_ADDR",  // ← new
};
```

Replace each placeholder with the actual address you copied in Step 4.

---

## Step 8 — Run the frontend

```bash
cd /Users/danieltan/StartupFundApp
npm run dev
```

Open http://localhost:8080 in Chrome.

---

## Step 9 — Test the full user flow

Use **Account 1** as campaign creator, **Accounts 2 + 3** as voters and contributors. Switch between them in MetaMask.

### 9a — Connect and auto-register (all three accounts)
1. Click **"Connect Wallet"** in the top navbar
2. MetaMask pops up → Approve the connection
3. A second MetaMask popup appears immediately — "Setting up your account…" → Confirm
4. ✅ Account 1 is now registered.
5. Switch MetaMask to Account 2 → Connect Wallet → Confirm the registration popup
6. Repeat for Account 3

### 9b — Create a campaign (Account 1)
1. Ensure MetaMask is on Account 1
2. Click **"Create"** in the navbar → fill in the campaign form:
   ```
   Title:             EcoFlow Smart Grid
   Short Description: Smart energy for everyone
   Description:       A decentralised smart grid powered by solar panels...
   Category:          Green Energy
   Tags:              renewable, climate, solar
   Goal Amount:       1   (ETH)
   Min Contribution:  0.001  (ETH)
   Deadline:          [pick 2 days from today]
   Token Symbol:      EFLOW
   ```
3. Click Create → MetaMask → Confirm
4. The campaign appears with **status = PENDING**. It cannot be funded yet.

### 9c — Community votes to approve (Accounts 2 + 3)
1. Switch MetaMask to Account 2
2. Open the campaign → find the **Voting Panel** in the sidebar
3. Click **Approve** → Confirm in MetaMask
4. Switch MetaMask to Account 3 → reload the campaign page → click **Approve** → Confirm

> At this point: 2 approves, 0 disapproves. Quorum (2) met. Approval rate = 100% (≥ 70%).

### 9d — Wait for the window to close, then finalize
1. Wait 2 minutes (the window you set in Step 6a)
2. Anyone can now click **"Finalize Vote — Activate or Reject Campaign"** in the Voting Panel
3. Confirm in MetaMask
4. ✅ Campaign transitions from PENDING → **ACTIVE**. The fund form appears.

### 9e — Fund the campaign (Account 2)
1. Make sure MetaMask is on Account 2
2. Open the campaign → in the sidebar, enter `1` ETH → click **Fund** → Confirm
3. Check:
   - Progress bar jumps to 100%
   - Campaign status changes to **FUNDED**

### 9f — Withdraw (Account 1)
1. Switch MetaMask to Account 1
2. Open the campaign → click **Withdraw** → Confirm
3. Check:
   - Account 1 ETH balance in Ganache increases by ~1 ETH (minus gas)
   - Account 2 receives SFT reward tokens

### 9g — Test the reject path (optional)
1. Create a new campaign as Account 1
2. Have Accounts 2 and 3 both click **Disapprove**
3. After the window closes, click **Finalize** → campaign becomes **REJECTED**
4. Fund form does not appear for rejected campaigns

### 9h — Test refund flow (optional)
To test refunds you need a campaign that expires without meeting its goal.
1. Create a new campaign with goal = 10 ETH (let it pass voting)
2. Fund it with 0.001 ETH (goal not met)
3. After the deadline passes, status flips to CANCELLED
4. Switch to the contributor account → click **Claim Refund**

---

## Common Errors and Fixes

| Error | Likely cause | Fix |
|-------|-------------|-----|
| `"Not authorized"` on setMinter/setAuthorized/setVotingContract | Calling from wrong account | Switch MetaMask to Account 1 (the deployer) |
| `"Wallet not registered"` | Account setup tx was skipped | Click Connect Wallet again — MetaMask will re-prompt |
| `"Campaign is not active"` | Campaign is still PENDING, or already FUNDED/CANCELLED/REJECTED | Check the Voting Panel. If PENDING, wait for the window and click Finalize |
| `"Voting not open"` on vote() | openVoting wasn't triggered | This happens if you call vote directly on CampaignVoting instead of via StartupFund.createCampaign path |
| `"Window still open"` on settleVoting | Voting window hasn't elapsed | Wait the remaining seconds shown in the panel |
| `"Already voted"` | Wallet already voted on this campaign | Switch to a different registered account |
| `"Not pending"` on activate/reject | Campaign already transitioned | Normal — settleVoting already ran |
| `"Contribution below minimum"` | Sent too little ETH | Use at least 0.001 ETH |
| `"Only campaign creator can withdraw"` | Wrong MetaMask account | Switch to the account that created the campaign |
| MetaMask shows wrong balance | Ganache was reset | Re-import the account private key into MetaMask |
| Frontend shows mock data after deploy | Addresses not updated | Update `src/lib/contractAddresses.ts` with real deployed addresses |
| Deploy fails with "invalid opcode" | EVM version too new | Check Step 3 — make sure EVM is set to **paris** |

---

## Quick Reference: What each contract does

| Contract | Role | Called by |
|----------|------|----------|
| `AccessControl` | Registers wallets, blocks bad actors, pauses platform | Frontend (register), Admin (pause/block) |
| `CampaignManager` | Stores campaign data, tags, status transitions | StartupFund (writes), CampaignVoting (activate/reject), Frontend (reads) |
| `FundingVault` | Holds ETH in escrow until campaign settles | StartupFund only |
| `RewardToken` | ERC-20 token minted to contributors on success | StartupFund (mints) |
| `CampaignVoting` | Community approval gate for new campaigns | Frontend (vote, settle), StartupFund (openVoting) |
| `StartupFund` | **Main contract** — all user actions route through here | MetaMask / Frontend |

## Quick Reference: Campaign status values

The `status` field returned by `getCampaignCore(id)` and `getStatus(id)` is a uint8:

| Value | Status    | Meaning |
|-------|-----------|---------|
| 0     | PENDING   | Awaiting community vote. Cannot be funded yet. |
| 1     | ACTIVE    | Approved. Accepting contributions. |
| 2     | FUNDED    | Goal met. Creator can withdraw. |
| 3     | CANCELLED | Deadline passed without meeting goal. Contributors can refund. |
| 4     | REJECTED  | Community voted it down. Terminal state. |
