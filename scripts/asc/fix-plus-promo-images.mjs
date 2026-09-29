// ガイドライン 2.3.2（プロモーション画像がアプリのスクショ）の却下に対応する一括スクリプト。
// 月額・年額のプロモーション画像を独自アートワークに差し替え、処理完了を待ってから2商品を再提出する。
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

// 画像のアップロード（年額は過去に 500 が返ったことがあるので数回やり直す）
for (const plan of PLANS) {
  for (let attempt = 1; ; attempt++) {
    try {
      run("upload-subscription-images.mjs", [plan.image, plan.id]);
      break;
    } catch (error) {
      if (attempt >= 3) throw error;
      console.log(`retry ${plan.id} (${attempt})`);
      await sleep(5000 * attempt);
    }
  }
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
