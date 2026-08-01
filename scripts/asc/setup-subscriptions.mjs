import { asc } from "./asc-lib.mjs";

const appId = "6760606408";
const groupReferenceName = "AirTalk Plus";
const groupDisplayName = "AirTalk Plus";
const subscriptions = [
  {
    referenceName: "AirTalk Plus Monthly",
    productId: "com.yuuki.AirTalk.plus.monthly",
    period: "ONE_MONTH",
    localizedName: "AirTalk Plus 月額",
  },
  {
    referenceName: "AirTalk Plus Yearly",
    productId: "com.yuuki.AirTalk.plus.yearly",
    period: "ONE_YEAR",
    localizedName: "AirTalk Plus 年額",
  },
];

async function listSubscriptionGroups() {
  const result = await asc(`/v1/apps/${appId}/subscriptionGroups?limit=50`);
  return result.data || [];
}

async function listGroupSubscriptions(groupId) {
  const result = await asc(`/v1/subscriptionGroups/${groupId}/subscriptions?limit=50`);
  return result.data || [];
}

async function createGroup() {
  return asc("/v1/subscriptionGroups", {
    method: "POST",
    body: {
      data: {
        type: "subscriptionGroups",
        attributes: {
          referenceName: groupReferenceName,
        },
        relationships: {
          app: {
            data: {
              type: "apps",
              id: appId,
            },
          },
        },
      },
    },
  });
}

async function createGroupLocalization(groupId) {
  return asc("/v1/subscriptionGroupLocalizations", {
    method: "POST",
    body: {
      data: {
        type: "subscriptionGroupLocalizations",
        attributes: {
          locale: "ja",
          name: groupDisplayName,
          customAppName: "AirTalk",
        },
        relationships: {
          subscriptionGroup: {
            data: {
              type: "subscriptionGroups",
              id: groupId,
            },
          },
        },
      },
    },
  });
}

async function listGroupLocalizations(groupId) {
  const result = await asc(`/v1/subscriptionGroups/${groupId}/subscriptionGroupLocalizations?limit=50`);
  return result.data || [];
}

async function updateGroupLocalization(localizationId) {
  return asc(`/v1/subscriptionGroupLocalizations/${localizationId}`, {
    method: "PATCH",
    body: {
      data: {
        type: "subscriptionGroupLocalizations",
        id: localizationId,
        attributes: {
          name: groupDisplayName,
          customAppName: "AirTalk",
        },
      },
    },
  });
}

async function ensureGroupLocalization(groupId) {
  const localizations = await listGroupLocalizations(groupId);
  const existing = localizations.find((item) => item.attributes?.locale === "ja");
  if (existing) return updateGroupLocalization(existing.id);
  return createGroupLocalization(groupId);
}

async function createSubscription(groupId, item) {
  return asc("/v1/subscriptions", {
    method: "POST",
    body: {
      data: {
        type: "subscriptions",
        attributes: {
          name: item.referenceName,
          productId: item.productId,
          subscriptionPeriod: item.period,
          familySharable: false,
          reviewNote: "AirTalk Plus unlocks optional profile presentation features such as Host badges, profile frames, saved profile presets, icebreakers, and additional reactions. Nearby discovery, invitations, 1-to-1 chat, reporting, and blocking remain free.",
        },
        relationships: {
          group: {
            data: {
              type: "subscriptionGroups",
              id: groupId,
            },
          },
        },
      },
    },
  });
}

function subscriptionLocalizationAttributes(item) {
  return {
    locale: "ja",
    name: item.localizedName,
    description: "Hostバッジ、プロフィールフレーム、プロフィールプリセット、アイスブレイク、追加リアクションを利用できます。",
  };
}

async function createSubscriptionLocalization(subscriptionId, item) {
  return asc("/v1/subscriptionLocalizations", {
    method: "POST",
    body: {
      data: {
        type: "subscriptionLocalizations",
        attributes: subscriptionLocalizationAttributes(item),
        relationships: {
          subscription: {
            data: {
              type: "subscriptions",
              id: subscriptionId,
            },
          },
        },
      },
    },
  });
}

async function listSubscriptionLocalizations(subscriptionId) {
  const result = await asc(`/v1/subscriptions/${subscriptionId}/subscriptionLocalizations?limit=50`);
  return result.data || [];
}

async function updateSubscriptionLocalization(localizationId, item) {
  const { locale, ...attributes } = subscriptionLocalizationAttributes(item);
  return asc(`/v1/subscriptionLocalizations/${localizationId}`, {
    method: "PATCH",
    body: {
      data: {
        type: "subscriptionLocalizations",
        id: localizationId,
        attributes,
      },
    },
  });
}

async function ensureSubscriptionLocalization(subscriptionId, item) {
  const localizations = await listSubscriptionLocalizations(subscriptionId);
  const existing = localizations.find((candidate) => candidate.attributes?.locale === "ja");
  if (existing) return updateSubscriptionLocalization(existing.id, item);
  return createSubscriptionLocalization(subscriptionId, item);
}

async function ignoreConflict(operation) {
  try {
    return await operation();
  } catch (error) {
    if (error.status === 409) return null;
    throw error;
  }
}

function summarizeSubscription(item) {
  return {
    id: item.id,
    name: item.attributes?.name,
    productId: item.attributes?.productId,
    state: item.attributes?.state,
    period: item.attributes?.subscriptionPeriod,
  };
}

async function main() {
  const groups = await listSubscriptionGroups();
  let group = groups.find((item) => item.attributes?.referenceName === groupReferenceName);

  if (!group) {
    const created = await createGroup();
    group = created.data;
    await ignoreConflict(() => ensureGroupLocalization(group.id));
    console.log(`created group ${group.id}`);
  } else {
    await ignoreConflict(() => ensureGroupLocalization(group.id));
    console.log(`using existing group ${group.id}`);
  }

  const existingSubscriptions = await listGroupSubscriptions(group.id);
  const outputs = [];

  for (const item of subscriptions) {
    let subscription = existingSubscriptions.find(
      (candidate) => candidate.attributes?.productId === item.productId
    );

    if (!subscription) {
      const created = await createSubscription(group.id, item);
      subscription = created.data;
      await ignoreConflict(() => ensureSubscriptionLocalization(subscription.id, item));
      console.log(`created subscription ${item.productId}: ${subscription.id}`);
    } else {
      await ignoreConflict(() => ensureSubscriptionLocalization(subscription.id, item));
      console.log(`using existing subscription ${item.productId}: ${subscription.id}`);
    }

    outputs.push(summarizeSubscription(subscription));
  }

  console.log(JSON.stringify({ group: { id: group.id, referenceName: groupReferenceName }, subscriptions: outputs }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  if (error.body) console.error(JSON.stringify(error.body, null, 2));
  process.exit(1);
});
