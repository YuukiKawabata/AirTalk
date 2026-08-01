import { asc } from "./asc-lib.mjs";

const appId = "6760606408";
const groupReferenceName = "AirTalk Plus";
const territory = "JPN";
const products = [
  {
    productId: "com.yuuki.AirTalk.plus.monthly",
    price: "300",
    introductoryOffer: {
      duration: "ONE_WEEK",
      offerMode: "FREE_TRIAL",
      numberOfPeriods: 1,
    },
  },
  {
    productId: "com.yuuki.AirTalk.plus.yearly",
    price: "2900",
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

async function listSubscriptions() {
  const groups = await asc(`/v1/apps/${appId}/subscriptionGroups?limit=50`);
  const group = (groups.data || []).find((item) => item.attributes?.referenceName === groupReferenceName);
  if (!group) throw new Error(`Subscription group not found: ${groupReferenceName}`);
  return listAll(`/v1/subscriptionGroups/${group.id}/subscriptions?limit=50`);
}

async function ensureAvailability(subscriptionId) {
  try {
    await asc(`/v1/subscriptions/${subscriptionId}/subscriptionAvailability`);
    console.log(`availability exists: ${subscriptionId}`);
    return;
  } catch (error) {
    if (error.status !== 404) throw error;
  }

  await asc("/v1/subscriptionAvailabilities", {
    method: "POST",
    body: {
      data: {
        type: "subscriptionAvailabilities",
        attributes: {
          availableInNewTerritories: true,
        },
        relationships: {
          subscription: {
            data: { type: "subscriptions", id: subscriptionId },
          },
          availableTerritories: {
            data: [{ type: "territories", id: territory }],
          },
        },
      },
    },
  });
  console.log(`created availability: ${subscriptionId}`);
}

async function findPricePoint(subscriptionId, price) {
  const points = await listAll(
    `/v1/subscriptions/${subscriptionId}/pricePoints?filter[territory]=${territory}&limit=200`
  );
  const point = points.find((item) => item.attributes?.customerPrice === price);
  if (!point) throw new Error(`Price point not found for ${subscriptionId}: ${territory} ${price}`);
  return point;
}

async function existingPrices(subscriptionId) {
  const result = await asc(`/v1/subscriptions/${subscriptionId}/prices?include=subscriptionPricePoint&limit=50`);
  const pointsById = new Map((result.included || []).map((item) => [item.id, item]));
  return (result.data || []).map((price) => {
    const pointId = price.relationships?.subscriptionPricePoint?.data?.id;
    return {
      price,
      point: pointId ? pointsById.get(pointId) : null,
    };
  });
}

async function ensurePrice(subscriptionId, price) {
  const prices = await existingPrices(subscriptionId);
  const existing = prices.find((item) => item.point?.attributes?.customerPrice === price);
  if (existing) {
    console.log(`price exists: ${subscriptionId} ${territory} ${price}`);
    return;
  }

  const point = await findPricePoint(subscriptionId, price);
  await asc("/v1/subscriptionPrices", {
    method: "POST",
    body: {
      data: {
        type: "subscriptionPrices",
        relationships: {
          subscription: {
            data: { type: "subscriptions", id: subscriptionId },
          },
          subscriptionPricePoint: {
            data: { type: "subscriptionPricePoints", id: point.id },
          },
        },
      },
    },
  });
  console.log(`created price: ${subscriptionId} ${territory} ${price}`);
}

async function ensureIntroductoryOffer(subscriptionId, offer) {
  if (!offer) return;

  const existing = await asc(`/v1/subscriptions/${subscriptionId}/introductoryOffers?limit=50`);
  const match = (existing.data || []).find(
    (item) =>
      item.attributes?.duration === offer.duration &&
      item.attributes?.offerMode === offer.offerMode &&
      item.attributes?.numberOfPeriods === offer.numberOfPeriods
  );
  if (match) {
    console.log(`introductory offer exists: ${subscriptionId}`);
    return;
  }

  await asc("/v1/subscriptionIntroductoryOffers", {
    method: "POST",
    body: {
      data: {
        type: "subscriptionIntroductoryOffers",
        attributes: {
          startDate: new Date().toISOString().slice(0, 10),
          duration: offer.duration,
          offerMode: offer.offerMode,
          numberOfPeriods: offer.numberOfPeriods,
          targetSubscriptionPlanType: "UPFRONT",
        },
        relationships: {
          subscription: {
            data: { type: "subscriptions", id: subscriptionId },
          },
          territory: {
            data: { type: "territories", id: territory },
          },
        },
      },
    },
  });
  console.log(`created introductory offer: ${subscriptionId}`);
}

const subscriptions = await listSubscriptions();

for (const product of products) {
  const subscription = subscriptions.find((item) => item.attributes?.productId === product.productId);
  if (!subscription) throw new Error(`Subscription not found: ${product.productId}`);

  await ensureAvailability(subscription.id);
  await ensurePrice(subscription.id, product.price);
  await ensureIntroductoryOffer(subscription.id, product.introductoryOffer);
}
