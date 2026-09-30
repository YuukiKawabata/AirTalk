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

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function currentImages(subscriptionId) {
  const body = await asc(`/v1/subscriptions/${encodeURIComponent(subscriptionId)}/images?limit=20`);
  return body.data ?? [];
}

// 公開中（承認済み）の画像は削除できず 409 が返る。その場合は残したまま新しい画像を追加し、
// 新しい画像が承認されると差し替わる。
async function deleteExistingImages(subscriptionId) {
  for (const image of await currentImages(subscriptionId)) {
    const state = image.attributes?.state;
    try {
      await asc(`/v1/subscriptionImages/${encodeURIComponent(image.id)}`, { method: "DELETE" });
      console.log(`deleted existing image ${image.id} (${state})`);
    } catch (error) {
      if (error.status !== 409) throw error;
      console.log(`kept existing image ${image.id} (${state}): ${error.body?.errors?.[0]?.title ?? "not deletable"}`);
    }
  }
}

// 5xx（過去に年額で 500 UNEXPECTED_ERROR が出た）は数回やり直す
async function withRetry(fn) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (!(error.status >= 500) || attempt >= 3) throw error;
      console.log(`retry after ${error.status} (${attempt})`);
      await sleep(5000 * attempt);
    }
  }
}

async function uploadSubscriptionImage(subscriptionId, filePath) {
  await deleteExistingImages(subscriptionId);

  const buffer = await fs.readFile(filePath);
  const stat = await fs.stat(filePath);
  const createBody = await withRetry(() => asc("/v1/subscriptionImages", {
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
  }));

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
