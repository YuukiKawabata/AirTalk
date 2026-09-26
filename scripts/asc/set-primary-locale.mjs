// アプリの主要言語を変更する。
// 公開中の全バージョンにその言語のスクショが必要なため、1.2.1 が公開されている間は
// Apple が 409 MISSING_SCREENSHOTS_PRIMARY_LOCALE を返す。1.3 公開後に実行する。
// 終了コード: 0 = 変更済み（または既にその言語）、2 = まだ変更できない、1 = その他のエラー
// 使い方: node scripts/asc/set-primary-locale.mjs [locale]   （既定は en-US）
import { asc } from "./asc-lib.mjs";

const APP_ID = "6760606408";
const locale = process.argv[2] ?? "en-US";

const before = (await asc(`/v1/apps/${APP_ID}`)).data.attributes.primaryLocale;
if (before === locale) {
  console.log(`• primaryLocale is already ${locale}`);
  process.exit(0);
}

try {
  await asc(`/v1/apps/${APP_ID}`, {
    method: "PATCH",
    body: { data: { type: "apps", id: APP_ID, attributes: { primaryLocale: locale } } },
  });
} catch (e) {
  const err = e.body?.errors?.[0];
  if (err?.code?.includes("MISSING_SCREENSHOTS_PRIMARY_LOCALE")) {
    console.log(`… cannot change yet: ${err.title}`);
    process.exit(2);
  }
  throw e;
}

const after = (await asc(`/v1/apps/${APP_ID}`)).data.attributes.primaryLocale;
console.log(`${after === locale ? "✓" : "✗"} primaryLocale: ${before} → ${after}`);
process.exit(after === locale ? 0 : 1);
