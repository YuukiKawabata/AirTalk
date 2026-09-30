// ガイドライン 2.3.2（プロモーション画像がアプリのスクショ）の却下に対応する一括スクリプト。
// 却下されたまま開いている Plus の提出を取り消して商品のロックを外し、月額・年額のプロモーション画像を
// 独自アートワークに差し替え、処理完了を待ってから2商品を再提出する。
// 使い方: node scripts/asc/fix-plus-promo-images.mjs
// 詳細: docs/app-review-reply-plus-promo-2.3.2.md
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { asc } from "./asc-lib.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const PROMO_DIR = join(HERE, "..", "..", "docs", "screenshots", "promo");
const PLANS = [
  { id: "6785129209", image: join(PROMO_DIR, "airtalk-plus-monthly.jpg") },
  { id: "6785129341", image: join(PROMO_DIR, "airtalk-plus-yearly.jpg") },
];
const PROCESSING = new Set(["AWAITING_UPLOAD", "UPLOAD_COMPLETE"]);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function run(script, args) {
  execFileSync(process.execPath, [join(HERE, script), ...args], { stdio: "inherit" });
}

async function imageStates(subscriptionId) {
  const body = await asc(`/v1/subscriptions/${subscriptionId}/images?limit=20`);
  return (body.data ?? []).map((item) => item.attributes?.state);
}

// 却下された Plus の提出（未解決の問題）。開いている間は商品がロックされ、画像を消すことも
// 追加することもできない（409 "version is not editable" / "change pending review"）。
const REJECTED_SUBMISSION_ID = "33ddeb23-4fb0-4771-b7db-c7ae44ed05e2";
// 提出項目 ID は base64("<提出ID>|<種類>|<対象ID>")。18 = サブスクリプション、19 = サブスクリプショングループ、
// 6 = アプリのバージョン。アプリのバージョンを巻き込まないよう、Plus の項目だけの提出に限って取り消す。
const PLUS_ITEM_TYPES = new Set(["18", "19"]);

function itemType(itemId) {
  return Buffer.from(itemId, "base64").toString("utf8").split("|")[1];
}

async function submissionState(id) {
  return (await asc(`/v1/reviewSubmissions/${id}`)).data.attributes.state;
}

async function unlockRejectedSubmission(id) {
  const state = await submissionState(id);
  console.log(`review submission ${id}: ${state}`);
  if (state !== "UNRESOLVED_ISSUES") return;

  const items = (await asc(`/v1/reviewSubmissions/${id}/items?limit=20`)).data ?? [];
  const types = items.map((item) => itemType(item.id));
  console.log(`  item types: ${types.join(", ")}`);
  if (items.length === 0 || !types.every((type) => PLUS_ITEM_TYPES.has(type))) {
    throw new Error(`${id} に Plus 以外の項目があるため取り消しません。ASC で確認してください`);
  }

  try {
    await asc(`/v1/reviewSubmissions/${id}`, {
      method: "PATCH",
      body: { data: { type: "reviewSubmissions", id, attributes: { canceled: true } } },
    });
    console.log("  canceled the submission");
  } catch (error) {
    // 取り消しを受け付けない場合は、却下された項目を1つずつ提出から外す
    console.log(`  cancel refused (${error.status} ${error.body?.errors?.[0]?.title ?? ""}); removing items instead`);
    for (const item of items) {
      await asc(`/v1/reviewSubmissionItems/${encodeURIComponent(item.id)}`, {
        method: "PATCH",
        body: { data: { type: "reviewSubmissionItems", id: item.id, attributes: { removed: true } } },
      });
      console.log(`  removed item (type ${itemType(item.id)})`);
    }
  }

  // 取り消しは CANCELING を経て終わる（最大 3 分待つ）
  for (let i = 0; i < 18; i++) {
    const current = await submissionState(id);
    console.log(`  state: ${current}`);
    if (current !== "UNRESOLVED_ISSUES" && current !== "CANCELING") return;
    await sleep(10000);
  }
  throw new Error(`${id} がまだ閉じていません。少し待ってからもう一度実行してください`);
}

await unlockRejectedSubmission(REJECTED_SUBMISSION_ID);

// 画像のアップロード（5xx のやり直しと、公開中で消せない画像の扱いは upload-subscription-images.mjs 側）
for (const plan of PLANS) {
  run("upload-subscription-images.mjs", [plan.image, plan.id]);
}

// Apple 側の画像処理が終わるまで待つ（最大 5 分）
for (const plan of PLANS) {
  for (let i = 0; ; i++) {
    const states = await imageStates(plan.id);
    console.log(`${plan.id} images: ${states.join(", ") || "(none)"}`);
    if (states.includes("FAILED")) throw new Error(`image processing failed for ${plan.id}`);
    if (states.length > 0 && !states.some((state) => PROCESSING.has(state))) break;
    if (i >= 30) throw new Error(`image for ${plan.id} is still processing; run submit-subscriptions.mjs later`);
    await sleep(10000);
  }
}

run("submit-subscriptions.mjs", []);
