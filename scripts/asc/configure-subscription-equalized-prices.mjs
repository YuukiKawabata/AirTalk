import { asc } from "./asc-lib.mjs";

const subscriptions = [
  {
    id: "6785129209",
    productId: "com.yuuki.AirTalk.plus.monthly",
    basePricePointId: "eyJzIjoiNjc4NTEyOTIwOSIsInQiOiJKUE4iLCJwIjoiMTAwMjYifQ",
  },
  {
    id: "6785129341",
    productId: "com.yuuki.AirTalk.plus.yearly",
    basePricePointId: "eyJzIjoiNjc4NTEyOTM0MSIsInQiOiJKUE4iLCJwIjoiMTAyMjMifQ",
  },
];

function nextPath(links) {
  if (!links?.next) return null;
  const url = new URL(links.next);
  return `${url.pathname}${url.search}`;
}

async function listAll(path) {
  const items = [];
  let current = path;
  while (current) {
    const page = await asc(current);
    items.push(...(page.data || []));
    current = nextPath(page.links);
  }
  return items;
}

async function existingPricePointIds(subscriptionId) {
  const prices = await listAll(`/v1/subscriptions/${subscriptionId}/prices?include=subscriptionPricePoint&limit=200`);
  return new Set(
    prices
      .map((price) => price.relationships?.subscriptionPricePoint?.data?.id)
      .filter(Boolean)
  );
}

async function equalizedPricePoints(basePricePointId) {
  const equalizations = await listAll(
    `/v1/subscriptionPricePoints/${encodeURIComponent(basePricePointId)}/equalizations?limit=200`
  );
  return [basePricePointId, ...equalizations.map((point) => point.id)];
}

async function createPrice(subscriptionId, pricePointId) {
  return asc("/v1/subscriptionPrices", {
    method: "POST",
    body: {
      data: {
        type: "subscriptionPrices",
        relationships: {
          subscription: {
            data: { type: "subscriptions", id: subscriptionId },
          },
          subscriptionPricePoint: {
            data: { type: "subscriptionPricePoints", id: pricePointId },
          },
        },
      },
    },
  });
}

async function createPriceWithRetry(subscriptionId, pricePointId) {
  let lastError;
  for (let attempt = 1; attempt <= 4; attempt += 1) {
    try {
      return await createPrice(subscriptionId, pricePointId);
    } catch (error) {
      if (error.status === 409) return null;
      lastError = error;
      if (error.status !== 500 && error.status !== 429) throw error;
      await new Promise((resolve) => setTimeout(resolve, attempt * 3000));
    }
  }
  throw lastError;
}

for (const subscription of subscriptions) {
  const existing = await existingPricePointIds(subscription.id);
  const targetPricePointIds = await equalizedPricePoints(subscription.basePricePointId);
  let created = 0;
  let skipped = 0;

  console.log(`${subscription.productId}: ${targetPricePointIds.length} target price points`);

  for (const pricePointId of targetPricePointIds) {
    if (existing.has(pricePointId)) {
      skipped += 1;
      continue;
    }

    try {
      const result = await createPriceWithRetry(subscription.id, pricePointId);
      if (result) created += 1;
      else skipped += 1;
    } catch (error) {
      throw error;
    }

    if ((created + skipped) % 25 === 0) {
      console.log(`${subscription.productId}: processed ${created + skipped}/${targetPricePointIds.length}`);
    }
  }

  console.log(`${subscription.productId}: created ${created}, skipped ${skipped}`);
}
