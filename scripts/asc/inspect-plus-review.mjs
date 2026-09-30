// AirTalk Plus と審査提出の状態を表示する（読み取りのみ。何も変更しない）。
// プロモーション画像の差し替えが「change pending review」で拒否されるときの調査用。
// 使い方: node scripts/asc/inspect-plus-review.mjs
import { asc } from "./asc-lib.mjs";

const APP_ID = "6760606408";
const GROUP_ID = "22193555";
const SUBSCRIPTION_IDS = ["6785129209", "6785129341"];

async function show(label, fn) {
  try {
    await fn();
  } catch (error) {
    console.log(`${label}: ${error.status} ${JSON.stringify(error.body?.errors?.map((e) => e.title ?? e.detail ?? e.code))}`);
  }
}

console.log("== subscriptions");
await show("group", async () => {
  const group = await asc(`/v1/subscriptionGroups/${GROUP_ID}`);
  console.log(`group ${GROUP_ID}: ${group.data.attributes.referenceName}`);
});
for (const id of SUBSCRIPTION_IDS) {
  await show(id, async () => {
    const sub = await asc(`/v1/subscriptions/${id}`);
    console.log(`${id} ${sub.data.attributes.productId}: ${sub.data.attributes.state}`);
    const images = await asc(`/v1/subscriptions/${id}/images?limit=20`);
    for (const image of images.data ?? []) {
      console.log(`  image ${image.id}: ${image.attributes.state} ${image.attributes.fileName ?? ""}`);
    }
    const locs = await asc(`/v1/subscriptions/${id}/subscriptionLocalizations`);
    console.log(`  localizations: ${locs.data.map((l) => `${l.attributes.locale}:${l.attributes.state}`).join(" ")}`);
  });
}

console.log("\n== review submissions (latest 10)");
await show("reviewSubmissions", async () => {
  const subs = await asc(`/v1/reviewSubmissions?filter[app]=${APP_ID}&limit=10`);
  for (const submission of subs.data ?? []) {
    const a = submission.attributes;
    console.log(`${submission.id}: ${a.state} platform=${a.platform} submitted=${a.submittedDate ?? "-"}`);
    await show(`  items of ${submission.id}`, async () => {
      const items = await asc(`/v1/reviewSubmissions/${submission.id}/items?limit=20`);
      for (const item of items.data ?? []) {
        const targets = Object.entries(item.relationships ?? {})
          .filter(([, rel]) => rel?.data)
          .map(([name, rel]) => `${name}:${rel.data.id}`);
        console.log(`  item ${item.id}: ${item.attributes?.state} ${targets.join(" ") || "(target not linked)"}`);
      }
    });
  }
});
