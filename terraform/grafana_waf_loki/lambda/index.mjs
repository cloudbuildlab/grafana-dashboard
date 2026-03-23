import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createGunzip } from "node:zlib";

const s3 = new S3Client({});
const LOKI_URL = process.env.LOKI_URL ?? "";

const __dirname = dirname(fileURLToPath(import.meta.url));
const centroids = JSON.parse(readFileSync(join(__dirname, "country-centroids.json"), "utf-8"));

/** Stay under Loki body limits; WAF JSON lines can be large. */
const MAX_BATCH_JSON_CHARS = 900_000;

/** ISO 3166-1 alpha-2 → bbox-centre lat/lon for Grafana Geomap panels. */
function enrichLineWithGeoCentroid(line) {
  try {
    const obj = JSON.parse(line);
    const raw = obj.httpRequest?.country;
    if (typeof raw !== "string") return line;
    const code = raw.trim().slice(0, 2).toUpperCase();
    if (code.length !== 2) return line;
    const c = centroids[code];
    if (!c) return line;
    obj.geo_lat = Number(c.lat.toFixed(5));
    obj.geo_lon = Number(c.lon.toFixed(5));
    return JSON.stringify(obj);
  } catch {
    return line;
  }
}

/**
 * SQS → Lambda handler.
 *
 * S3 sends object-created events to the SQS queue; each SQS record's body is
 * a JSON string containing the S3 event envelope ({ Records: [...] }).
 *
 * Returning { batchItemFailures } lets SQS retry only the messages that failed
 * without re-processing the rest of the batch.
 *
 * @param {import("aws-lambda").SQSEvent} event
 */
export async function handler(event) {
  if (!LOKI_URL) {
    throw new Error("LOKI_URL is not set; fix Terraform wiring to the Loki push endpoint");
  }

  const batchItemFailures = [];

  for (const sqsRecord of event.Records ?? []) {
    try {
      let s3Event;
      try {
        s3Event = JSON.parse(sqsRecord.body);
      } catch {
        console.warn(JSON.stringify({ msg: "unparseable SQS body", messageId: sqsRecord.messageId }));
        continue;
      }

      // S3 sends a test event when the notification is first configured — ignore it.
      if (s3Event.Event === "s3:TestEvent") continue;

      for (const s3Record of s3Event.Records ?? []) {
        const bucket = s3Record.s3.bucket.name;
        const key = decodeURIComponent(s3Record.s3.object.key.replace(/\+/g, " "));
        await ingestObject(bucket, key);
      }
    } catch (err) {
      console.error(JSON.stringify({ msg: "failed to process SQS record", messageId: sqsRecord.messageId, error: String(err) }));
      batchItemFailures.push({ itemIdentifier: sqsRecord.messageId });
    }
  }

  return { batchItemFailures };
}

async function ingestObject(bucket, key) {
  const out = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  const { Body, ContentEncoding } = out;

  const gzipByKey = key.endsWith(".gz");
  const gzipByHeader = ContentEncoding === "gzip";
  const stream = gzipByKey || gzipByHeader ? Body.pipe(createGunzip()) : Body;

  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  const text = Buffer.concat(chunks).toString("utf-8");

  const lines = text.split("\n").filter((l) => l.trim());
  if (!lines.length) return;

  const values = lines.map((line) => {
    const enriched = enrichLineWithGeoCentroid(line);
    let tsNs = String(BigInt(Date.now()) * 1_000_000n);
    try {
      const obj = JSON.parse(enriched);
      if (typeof obj.timestamp === "number") {
        tsNs = String(BigInt(obj.timestamp) * 1_000_000n);
      }
    } catch {
      // non-JSON line: use current time
    }
    return [tsNs, enriched];
  });

  const labels = { source: "waf", bucket };
  for (const batch of chunkValues(values)) {
    await pushToLoki(batch, labels);
  }
}

/** Split into multiple Loki requests so no single POST exceeds safe size. */
function chunkValues(values) {
  const batches = [];
  let batch = [];
  let approx = 0;

  for (const pair of values) {
    const [tsNs, line] = pair;
    const lineCost = tsNs.length + line.length + 8;
    if (batch.length > 0 && approx + lineCost > MAX_BATCH_JSON_CHARS) {
      batches.push(batch);
      batch = [];
      approx = 0;
    }
    batch.push(pair);
    approx += lineCost;
  }
  if (batch.length) batches.push(batch);
  return batches;
}

async function pushToLoki(values, labels) {
  const payload = { streams: [{ stream: labels, values }] };
  const res = await fetch(LOKI_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Loki push failed ${res.status}: ${detail.slice(0, 500)}`);
  }
}
