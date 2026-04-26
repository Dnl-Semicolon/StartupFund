// ─────────────────────────────────────────────────────────────────────────────
// StartupFund — one-shot deploy + wire script for Remix IDE
//
// Deploys all 6 contracts, runs all 5 authorizations, applies demo shortcuts
// (120s voting window, quorum 2), and dumps the TypeScript address block
// you paste into /Users/danieltan/StartupFundApp/src/lib/contractAddresses.ts.
// Also writes scripts/deployed-addresses.json as a second source of truth.
//
// How to run:
//   1. Compile every .sol file (Solidity Compiler → Advanced → EVM = paris)
//   2. Deploy & run tab → Environment = "Injected Provider - MetaMask"
//   3. Right-click THIS file in the explorer → "Run" (or Ctrl+Shift+S)
//   4. Approve ~13 MetaMask popups (6 deploys + 5 auths + 2 demo config)
//   5. Copy the TS block at the end → paste over contractAddresses.ts
//
// Total expected popups: 13. If one fails, re-run — each step is idempotent
// until contracts are deployed; after that, re-runs would duplicate.
// ─────────────────────────────────────────────────────────────────────────────

import { deploy } from './ethers-lib'

// ─────────────────────────────────────────────────────────────────────────────
// CONFIG — edit these before running. Saved in-memory at deploy time into
// CampaignVoting via setVotingWindow / setQuorum. You can also change them
// later by calling those setters manually in Remix.
// ─────────────────────────────────────────────────────────────────────────────

/** Voting window length in SECONDS. Pick ONE. */
// const VOTING_WINDOW_SECONDS = 120          // demo: 2 minutes (fast demo)
// const VOTING_WINDOW_SECONDS = 60 * 5     // 5 minutes
const VOTING_WINDOW_SECONDS = 60 * 10    // 10 minutes
// const VOTING_WINDOW_SECONDS = 60 * 30    // 30 minutes
// const VOTING_WINDOW_SECONDS = 60 * 60    // 1 hour
// const VOTING_WINDOW_SECONDS = 60 * 60 * 6    // 6 hours
// const VOTING_WINDOW_SECONDS = 60 * 60 * 24   // 24 hours
// const VOTING_WINDOW_SECONDS = 60 * 60 * 72   // 72 hours (real-world default)

/** Minimum total votes before approval-threshold decision applies. Pick ONE. */
const QUORUM = 2                           // demo: 2 votes (easy to reach)
// const QUORUM = 5                         // small community
// const QUORUM = 10                        // real-world default

/** Set false to skip the demo config setters entirely — contract keeps its
 *  built-in defaults (72h / 10 votes). */
const APPLY_DEMO_CONFIG = true

// ─────────────────────────────────────────────────────────────────────────────

const step = (n: number, total: number, label: string) =>
  console.log(`\n[${n}/${total}] ${label}`)

;(async () => {
  const TOTAL = APPLY_DEMO_CONFIG ? 13 : 11
  let n = 0

  try {
    console.log('═══════════════════════════════════════════════════════════')
    console.log(' StartupFund — automated deploy + wire')
    console.log('═══════════════════════════════════════════════════════════')

    // ── Phase 1: Deploy (6 txs) ─────────────────────────────────────────────

    step(++n, TOTAL, 'Deploying AccessControl…')
    const accessControl = await deploy('AccessControl', [])
    console.log(`   ✓ ${accessControl.address}`)

    step(++n, TOTAL, 'Deploying CampaignManager…')
    const campaignManager = await deploy('CampaignManager', [])
    console.log(`   ✓ ${campaignManager.address}`)

    step(++n, TOTAL, 'Deploying FundingVault…')
    const fundingVault = await deploy('FundingVault', [])
    console.log(`   ✓ ${fundingVault.address}`)

    step(++n, TOTAL, 'Deploying RewardToken…')
    const rewardToken = await deploy('RewardToken', [])
    console.log(`   ✓ ${rewardToken.address}`)

    step(++n, TOTAL, 'Deploying CampaignVoting(CM, AC)…')
    const campaignVoting = await deploy('CampaignVoting', [
      campaignManager.address,
      accessControl.address,
    ])
    console.log(`   ✓ ${campaignVoting.address}`)

    step(++n, TOTAL, 'Deploying StartupFund(CM, FV, RT, AC, CV)…')
    const startupFund = await deploy('StartupFund', [
      campaignManager.address,
      fundingVault.address,
      rewardToken.address,
      accessControl.address,
      campaignVoting.address,
    ])
    console.log(`   ✓ ${startupFund.address}`)

    // ── Phase 2: Authorize (5 txs) ──────────────────────────────────────────

    step(++n, TOTAL, 'RewardToken.setMinter(StartupFund)…')
    await (await rewardToken.setMinter(startupFund.address)).wait()
    console.log('   ✓')

    step(++n, TOTAL, 'CampaignManager.setAuthorized(StartupFund)…')
    await (await campaignManager.setAuthorized(startupFund.address)).wait()
    console.log('   ✓')

    step(++n, TOTAL, 'FundingVault.setAuthorized(StartupFund)…')
    await (await fundingVault.setAuthorized(startupFund.address)).wait()
    console.log('   ✓')

    step(++n, TOTAL, 'CampaignManager.setVotingContract(CampaignVoting)…')
    await (await campaignManager.setVotingContract(campaignVoting.address)).wait()
    console.log('   ✓')

    step(++n, TOTAL, 'CampaignVoting.setAuthorized(StartupFund)…')
    await (await campaignVoting.setAuthorized(startupFund.address)).wait()
    console.log('   ✓')

    // ── Phase 3: Demo config (2 txs, optional) ──────────────────────────────

    if (APPLY_DEMO_CONFIG) {
      const hrs  = (VOTING_WINDOW_SECONDS / 3600).toFixed(2).replace(/\.?0+$/, '')
      const mins = (VOTING_WINDOW_SECONDS / 60).toFixed(2).replace(/\.?0+$/, '')
      const readable = VOTING_WINDOW_SECONDS >= 3600
        ? `${hrs} hr`
        : `${mins} min`

      step(++n, TOTAL, `CampaignVoting.setVotingWindow(${VOTING_WINDOW_SECONDS})  — ${readable}`)
      await (await campaignVoting.setVotingWindow(VOTING_WINDOW_SECONDS)).wait()
      console.log('   ✓')

      step(++n, TOTAL, `CampaignVoting.setQuorum(${QUORUM})  — ${QUORUM} vote${QUORUM === 1 ? '' : 's'} minimum`)
      await (await campaignVoting.setQuorum(QUORUM)).wait()
      console.log('   ✓')
    } else {
      console.log('\n(skipped demo config — contract defaults: 72h window, quorum 10)')
    }

    // ── Phase 4: Output ─────────────────────────────────────────────────────

    const addresses = {
      startupFund:     startupFund.address,
      campaignManager: campaignManager.address,
      fundingVault:    fundingVault.address,
      rewardToken:     rewardToken.address,
      accessControl:   accessControl.address,
      campaignVoting:  campaignVoting.address,
    }

    const tsBlock =
`export const CONTRACT_ADDRESSES = {
  startupFund:     "${addresses.startupFund}",
  campaignManager: "${addresses.campaignManager}",
  fundingVault:    "${addresses.fundingVault}",
  rewardToken:     "${addresses.rewardToken}",
  accessControl:   "${addresses.accessControl}",
  campaignVoting:  "${addresses.campaignVoting}",
};

// Chain ID for Ganache
export const CHAIN_ID = 1337;
`

    // Persist a JSON copy in the workspace
    try {
      await remix.call(
        'fileManager',
        'writeFile',
        'scripts/deployed-addresses.json',
        JSON.stringify(addresses, null, 2) + '\n'
      )
      console.log('\nWrote scripts/deployed-addresses.json')
    } catch (err) {
      console.log('\n(note) Could not write deployed-addresses.json:',
        err && (err as any).message ? (err as any).message : err)
    }

    console.log('\n═══════════════════════════════════════════════════════════')
    console.log(' DONE — paste this over src/lib/contractAddresses.ts')
    console.log('═══════════════════════════════════════════════════════════\n')
    console.log(tsBlock)

  } catch (e: any) {
    console.error(`\n[FAILED at step ${n}/${TOTAL}]`)
    console.error(e && e.message ? e.message : e)
    console.error('\nFix the underlying issue and re-run. If some contracts already deployed,')
    console.error('you may need a fresh Ganache workspace or MetaMask "Clear activity data".')
  }
})()
