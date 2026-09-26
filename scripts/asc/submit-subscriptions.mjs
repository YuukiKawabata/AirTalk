// AirTalk Plus の商品（ローカライズの変更を含む）を審査に提出する。
// 使い方: node scripts/asc/submit-subscriptions.mjs
import { asc } from "./asc-lib.mjs";

const SUBSCRIPTION_IDS = ["6785129209", "6785129341"];

for (const id of SUBSCRIPTION_IDS) {
  try {
    const res = await asc("/v1/subscriptionSubmissions", {
      method: "POST",
      body: {
        data: {
          type: "subscriptionSubmissions",
          relationships: { subscription: { data: { type: "subscriptions", id } } },
        },
      },
    });
    console.log(`✓ submitted subscription ${id} (${res.data.id})`);
  } catch (e) {
    console.log(`✗ subscription ${id}: ${e.status} ${JSON.stringify(e.body?.errors?.map((x) => x.detail ?? x.code))}`);
    process.exitCode = 1;
  }
}

for (const id of SUBSCRIPTION_IDS) {
  const sub = await asc(`/v1/subscriptions/${id}`);
  const locs = await asc(`/v1/subscriptions/${id}/subscriptionLocalizations`);
  console.log(`${id}: ${sub.data.attributes.state} / ${locs.data.map((l) => `${l.attributes.locale}:${l.attributes.state}`).join(" ")}`);
}
