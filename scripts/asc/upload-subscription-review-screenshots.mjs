import { existsSync, readFileSync, statSync } from "node:fs";
import { basename } from "node:path";
import { asc, makeToken } from "./asc-lib.mjs";

const [, , screenshotPath, ...subscriptionIds] = process.argv;

function usage() {
  console.error("Usage: node scripts/asc/upload-subscription-review-screenshots.mjs SCREENSHOT_PATH SUBSCRIPTION_ID [SUBSCRIPTION_ID...]");
  process.exit(1);
}

function requestHeaders(headers = []) {
  const result = {};
  for (const header of headers) {
    result[header.name] = header.value;
  }
  return result;
}

async function currentReviewScreenshotId(subscriptionId) {
  const body = await asc(`/v1/subscriptions/${encodeURIComponent(subscriptionId)}?include=appStoreReviewScreenshot`);
  const reviewScreenshot = (body.included || []).find(
    (item) => item.type === "subscriptionAppStoreReviewScreenshots"
  );
  return reviewScreenshot?.id || body.data?.relationships?.appStoreReviewScreenshot?.data?.id || null;
}

async function deleteExistingReviewScreenshot(subscriptionId) {
  const id = await currentReviewScreenshotId(subscriptionId);
  if (!id) return null;
  await asc(`/v1/subscriptionAppStoreReviewScreenshots/${encodeURIComponent(id)}`, { method: "DELETE" });
  return id;
}

async function uploadReviewScreenshot(subscriptionId, filePath) {
  const deletedId = await deleteExistingReviewScreenshot(subscriptionId);
  if (deletedId) {
    console.log(`  - deleted existing ${deletedId}`);
  }

  const fileName = basename(filePath);
  const fileSize = statSync(filePath).size;
  const createBody = await asc("/v1/subscriptionAppStoreReviewScreenshots", {
    method: "POST",
    body: {
      data: {
        type: "subscriptionAppStoreReviewScreenshots",
        attributes: { fileName, fileSize },
        relationships: {
          subscription: {
            data: { type: "subscriptions", id: subscriptionId },
          },
        },
      },
    },
  });

  const screenshot = createBody.data;
  const bytes = readFileSync(filePath);
  for (const operation of screenshot.attributes.uploadOperations || []) {
    const offset = Number(operation.offset || 0);
    const length = Number(operation.length || bytes.length);
    const chunk = bytes.subarray(offset, offset + length);
    const response = await fetch(operation.url, {
      method: operation.method,
      headers: requestHeaders(operation.requestHeaders),
      body: chunk,
    });
    if (!response.ok) {
      throw new Error(`Upload failed for ${fileName}: ${response.status} ${await response.text()}`);
    }
  }

  const uploaded = await asc(`/v1/subscriptionAppStoreReviewScreenshots/${encodeURIComponent(screenshot.id)}`, {
    method: "PATCH",
    body: {
      data: {
        type: "subscriptionAppStoreReviewScreenshots",
        id: screenshot.id,
        attributes: { uploaded: true },
      },
    },
  });

  return uploaded.data;
}

if (!screenshotPath || subscriptionIds.length === 0) {
  usage();
}

if (!existsSync(screenshotPath)) {
  throw new Error(`Screenshot does not exist: ${screenshotPath}`);
}

// Make token once before upload operations so auth/env errors fail before any delete/create.
makeToken();

console.log(`Review screenshot: ${screenshotPath}`);
for (const subscriptionId of subscriptionIds) {
  console.log(`Subscription: ${subscriptionId}`);
  const screenshot = await uploadReviewScreenshot(subscriptionId, screenshotPath);
  console.log(
    `  uploaded ${screenshot.id} (${screenshot.attributes?.assetDeliveryState?.state || screenshot.attributes?.sourceFileChecksum || "processing"})`
  );
}
