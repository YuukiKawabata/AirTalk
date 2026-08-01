import fs from "node:fs/promises";
import { asc, makeToken } from "./asc-lib.mjs";

const [, , imagePath, ...subscriptionIds] = process.argv;

if (!imagePath || subscriptionIds.length === 0) {
  console.error("Usage: node scripts/asc/upload-subscription-images.mjs IMAGE_PATH SUBSCRIPTION_ID [SUBSCRIPTION_ID...]");
  process.exit(1);
}

async function uploadChunk(operation, buffer) {
  const offset = Number(operation.offset ?? 0);
  const length = Number(operation.length ?? buffer.length);
  const chunk = buffer.subarray(offset, offset + length);
  const token = makeToken();

  const response = await fetch(operation.url, {
    method: operation.method ?? "PUT",
    headers: {
      Authorization: `Bearer ${token}`,
      ...Object.fromEntries((operation.requestHeaders ?? []).map((header) => [header.name, header.value])),
    },
    body: chunk,
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`upload failed ${response.status}: ${body}`);
  }
}

async function currentImageIds(subscriptionId) {
  const body = await asc(`/v1/subscriptions/${encodeURIComponent(subscriptionId)}/images?limit=20`);
  return (body.data ?? []).map((item) => item.id);
}

async function deleteExistingImages(subscriptionId) {
  const ids = await currentImageIds(subscriptionId);
  for (const id of ids) {
    await asc(`/v1/subscriptionImages/${encodeURIComponent(id)}`, { method: "DELETE" });
    console.log(`deleted existing image ${id}`);
  }
}

async function uploadSubscriptionImage(subscriptionId, filePath) {
  await deleteExistingImages(subscriptionId);

  const buffer = await fs.readFile(filePath);
  const stat = await fs.stat(filePath);
  const createBody = await asc("/v1/subscriptionImages", {
    method: "POST",
    body: {
      data: {
        type: "subscriptionImages",
        attributes: {
          fileName: "SOURCE",
          fileSize: stat.size,
        },
        relationships: {
          subscription: {
            data: { type: "subscriptions", id: subscriptionId },
          },
        },
      },
    },
  });

  const image = createBody.data;
  for (const operation of image.attributes.uploadOperations ?? []) {
    await uploadChunk(operation, buffer);
  }

  return asc(`/v1/subscriptionImages/${encodeURIComponent(image.id)}`, {
    method: "PATCH",
    body: {
      data: {
        type: "subscriptionImages",
        id: image.id,
        attributes: { uploaded: true },
      },
    },
  });
}

for (const subscriptionId of subscriptionIds) {
  console.log(`Subscription: ${subscriptionId}`);
  const image = await uploadSubscriptionImage(subscriptionId, imagePath);
  console.log(
    JSON.stringify(
      {
        id: image.data.id,
        state: image.data.attributes?.state,
        asset: image.data.attributes?.imageAsset,
      },
      null,
      2
    )
  );
}
