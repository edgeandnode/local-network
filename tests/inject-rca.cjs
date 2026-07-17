// Encode a SignedRCA payload (ABI-encoded, empty signature) for injecting a
// pending_rca_proposals row into the indexer DB. Mirrors toolshed's decodeSignedRCA
// wire format. Run with NODE_PATH pointing at the indexer source's node_modules:
//   NODE_PATH=<indexer>/node_modules node tests/inject-rca.cjs --deployment-bytes32 0x.. [opts]
// Prints JSON: { payloadHex, agreementIdInputs, rca }.
const { ethers } = require('ethers')
const { decodeSignedRCA } = require('@graphprotocol/toolshed')

const args = Object.fromEntries(
  process.argv.slice(2).reduce((a, v, i, arr) => {
    if (v.startsWith('--')) a.push([v.slice(2), arr[i + 1]])
    return a
  }, []),
)

// Deterministic hardhat addresses (per-deploy stable).
const RAM = '0x3347b4d90ebe72befb30444c9966b2b990ae9fcb' // payer (RecurringAgreementManager)
const SUBGRAPH_SERVICE = '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9'
const INDEXER = '0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3'
const RECURRING_COLLECTOR = '0x4A679253410272dd5232B3Ff7cF5dbB88f295319'

const deploymentBytes32 = args['deployment-bytes32']
if (!deploymentBytes32) throw new Error('--deployment-bytes32 required')
const nowSec = BigInt(args['now'] ?? Math.floor(Date.now() / 1000))
const deadline = BigInt(args['deadline'] ?? nowSec + 600n) // default 10m future
const nonce = BigInt(args['nonce'] ?? Math.floor(Math.random() * 1e15))
const conditions = BigInt(args['conditions'] ?? 2) // RC_CONDITION_AGREEMENT_OWNER (payer=RAM)
const endsAt = BigInt(args['ends-at'] ?? '18446744073709551615') // max uint64 = never
const tokensPerSecond = BigInt(args['tokens-per-second'] ?? '0x2316a9e9a22d')
const tokensPerEntityPerSecond = BigInt(args['tokens-per-entity-per-second'] ?? '0xe5f4c8f4')
const maxOngoing = BigInt(args['max-ongoing'] ?? '0x1b69b4be86b292')
const maxInitial = BigInt(args['max-initial'] ?? 0)
const minSecs = BigInt(args['min-seconds'] ?? 60)
const maxSecs = BigInt(args['max-seconds'] ?? 660)
const signature = args['signature'] ?? '0x' // agent ignores it (main-dips #1241)

const coder = ethers.AbiCoder.defaultAbiCoder()
const TERMS_V1 = 'tuple(uint256 tokensPerSecond, uint256 tokensPerEntityPerSecond)'
const ACCEPT_META = 'tuple(bytes32 subgraphDeploymentId, uint8 version, bytes terms)'
const RCA =
  'tuple(uint64 deadline, uint64 endsAt, address payer, address dataService, address serviceProvider, uint256 maxInitialTokens, uint256 maxOngoingTokensPerSecond, uint32 minSecondsPerCollection, uint32 maxSecondsPerCollection, uint16 conditions, uint256 nonce, bytes metadata)'
const SIGNED_RCA = `tuple(${RCA} rca, bytes signature)`

const terms = coder.encode([TERMS_V1], [{ tokensPerSecond, tokensPerEntityPerSecond }])
// version is the on-chain enum IndexingAgreementVersion { V1 } — so V1 == 0 (NOT 1).
// A value of 1 is out-of-range and makes the contract's abi.decode into the enum revert.
const metadata = coder.encode([ACCEPT_META], [{ subgraphDeploymentId: deploymentBytes32, version: 0, terms }])
const rca = {
  deadline, endsAt, payer: RAM, dataService: SUBGRAPH_SERVICE, serviceProvider: INDEXER,
  maxInitialTokens: maxInitial, maxOngoingTokensPerSecond: maxOngoing,
  minSecondsPerCollection: minSecs, maxSecondsPerCollection: maxSecs, conditions, nonce, metadata,
}
const payloadHex = coder.encode([SIGNED_RCA], [{ rca, signature }])
// offerData for RAM.offerAgreement(collector, OFFER_TYPE_NEW, offerData) = abi.encode(rca).
const offerDataHex = coder.encode([RCA], [rca])

// Self-validate: round-trip through toolshed's decoder (the exact fn the agent uses).
const decoded = decodeSignedRCA(payloadHex)
if (decoded.rca.deadline !== deadline || decoded.rca.nonce !== nonce || decoded.rca.payer.toLowerCase() !== RAM) {
  throw new Error('round-trip validation FAILED: ' + JSON.stringify(decoded, (_, v) => (typeof v === 'bigint' ? v.toString() : v)))
}
const meta = require('@graphprotocol/toolshed').decodeAcceptIndexingAgreementMetadata(decoded.rca.metadata)
if (meta.subgraphDeploymentId.toLowerCase() !== deploymentBytes32.toLowerCase()) {
  throw new Error('metadata deployment mismatch: ' + meta.subgraphDeploymentId)
}

console.log(
  JSON.stringify(
    {
      payloadHex,
      offerDataHex,
      agreementIdInputs: { payer: RAM, dataService: SUBGRAPH_SERVICE, serviceProvider: INDEXER, deadline: deadline.toString(), nonce: nonce.toString(), recurringCollector: RECURRING_COLLECTOR },
      rca: { deadline: deadline.toString(), nonce: nonce.toString(), conditions: conditions.toString(), deployment: deploymentBytes32 },
    },
    null,
    2,
  ),
)
