import fs from "node:fs/promises";
import { basename } from "node:path";
import { createHash } from "node:crypto";
import { asc } from "./asc-lib.mjs";

const [, , imagePath, ...subscriptionIds] = process.argv;

if (!imagePath || subscriptionIds.length === 0) {
  console.error("Usage: node scripts/asc/upload-subscription-images.mjs IMAGE_PATH SUBSCRIPTION_ID [SUBSCRIPTION_ID...]");
  process.exit(1);
}

async function uploadChunk(operation, buffer) {
  const offset = Number(operation.offset ?? 0);
  const length = Number(operation.length ?? buffer.length);
  const chunk = buffer.subarray(offset, offset + length);

  // 署名付き URL なので、指定されたヘッダー以外（ASC の Authorization など）を付けると 400 になる
  const response = await fetch(operation.url, {
    method: operation.method ?? "PUT",
    headers: Object.fromEntries((operation.requestHeaders ?? []).map((header) => [header.name, header.value])),
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

// 5xx（2026-06 の年額、2026-09 の月額で 500 UNEXPECTED_ERROR が出た）は数回やり直す
async function withRetry(fn) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (!(error.status >= 500) || attempt >= 4) throw error;
      console.log(`retry after ${error.status} (${attempt})`);
      await sleep(10000 * attempt);
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
          fileName: basename(filePath),
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
        attributes: { uploaded: true, sourceFileChecksum: createHash("md5").update(buffer).digest("hex") },
      },
    },
  });
}

for (const subscriptionId of subscriptionIds) {
  console.log(`Subscription: ${subscriptionId}`);
  let image;
  try {
    image = await uploadSubscriptionImage(subscriptionId, imagePath);
  } catch (error) {
    if (!(error.status >= 500)) throw error;
    // Apple 側の障害で画像を作れない。呼び出し側が区別できるよう終了コード 3 で終える
    console.error(`image upload failed with ${error.status}: ${error.body?.errors?.[0]?.detail ?? ""}`);
    process.exit(3);
  }
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
