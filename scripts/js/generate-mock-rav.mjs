#!/usr/bin/env node
/**
 * Generate a mock signed RAV and insert it into the database.
 *
 * Usage:
 *   node generate-mock-rav.mjs \
 *     --allocation-id 0x... \
 *     --data-service 0x... \
 *     --collector 0x... \
 *     --timestamp-ns 1234567890000000000 \
 *     [--value 0.1] \
 *     [--db postgres://postgres@localhost:5432/indexer_components_1]
 */

import { parseArgs } from "node:util";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { config } from "dotenv";
import pg from "pg";
import { generateSignedRAV } from "@graphprotocol/toolshed";

const __dirname = dirname(fileURLToPath(import.meta.url));
config({ path: resolve(__dirname, "../../.env") });

function parseCliArgs() {
  const { values } = parseArgs({
    options: {
      "allocation-id": { type: "string" },
      "data-service": { type: "string" },
      collector: { type: "string" },
      "timestamp-ns": { type: "string" },
      value: { type: "string", default: "0.1" },
      db: { type: "string", default: "postgres://postgres@localhost:5432/indexer_components_1" },
    },
  });

  const required = ["allocation-id", "data-service", "collector", "timestamp-ns"];
  for (const key of required) {
    if (!values[key]) {
      console.error(`Missing required argument: --${key}`);
      process.exit(1);
    }
  }

  return values;
}

function getEnvVar(name) {
  const value = process.env[name];
  if (!value) {
    console.error(`Missing environment variable: ${name}`);
    process.exit(1);
  }
  return value;
}

function grtToWei(grt) {
  const [whole, decimal = ""] = grt.split(".");
  const paddedDecimal = decimal.padEnd(18, "0").slice(0, 18);
  return BigInt(whole + paddedDecimal);
}

function stripHexPrefix(hex) {
  return hex.startsWith("0x") ? hex.slice(2) : hex;
}

async function main() {
  const args = parseCliArgs();

  const payer = getEnvVar("ACCOUNT0_ADDRESS");
  const serviceProvider = getEnvVar("RECEIVER_ADDRESS");
  const signerPrivateKey = getEnvVar("ACCOUNT1_SECRET");
  const chainId = parseInt(getEnvVar("CHAIN_ID"), 10);

  const allocationId = args["allocation-id"];
  const dataService = args["data-service"];
  const graphTallyCollectorAddress = args["collector"];
  const timestampNs = BigInt(args["timestamp-ns"]);
  const valueAggregate = grtToWei(args["value"]);
  const metadata = "0x";

  console.log("Generating signed RAV...");
  console.log("  allocationId:", allocationId);
  console.log("  payer:", payer);
  console.log("  serviceProvider:", serviceProvider);
  console.log("  dataService:", dataService);
  console.log("  timestampNs:", timestampNs.toString());
  console.log("  valueAggregate:", valueAggregate.toString(), "(wei)");

  const { signature } = await generateSignedRAV(
    allocationId,
    payer,
    serviceProvider,
    dataService,
    timestampNs,
    valueAggregate,
    metadata,
    signerPrivateKey,
    graphTallyCollectorAddress,
    chainId
  );

  console.log("RAV generated successfully");
  console.log("  signature:", signature);

  console.log("Connecting to database...");
  const client = new pg.Client({ connectionString: args["db"] });
  await client.connect();

  try {
    const collectionId = stripHexPrefix(allocationId).toLowerCase().padStart(64, "0");

    const insertQuery = `
      INSERT INTO tap_horizon_ravs (
        signature,
        collection_id,
        payer,
        data_service,
        service_provider,
        timestamp_ns,
        value_aggregate,
        metadata,
        last,
        final,
        redeemed_at,
        created_at,
        updated_at
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13
      )
    `;

    const now = new Date();
    const values = [
      Buffer.from(stripHexPrefix(signature), "hex"),
      collectionId,
      stripHexPrefix(payer).toLowerCase(),
      stripHexPrefix(dataService).toLowerCase(),
      stripHexPrefix(serviceProvider).toLowerCase(),
      timestampNs.toString(),
      valueAggregate.toString(),
      Buffer.from(stripHexPrefix(metadata) || "", "hex"),
      true,  // last
      false, // final
      null,  // redeemed_at
      now,   // created_at
      now,   // updated_at
    ];

    await client.query(insertQuery, values);
    console.log("RAV inserted into database successfully");
  } finally {
    await client.end();
  }

  console.log("Done!");
}

main().catch((error) => {
  console.error("Script failed:", error);
  process.exit(1);
});
