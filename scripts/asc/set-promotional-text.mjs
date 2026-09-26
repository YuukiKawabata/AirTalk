// 公開中バージョンのプロモーションテキストを更新する（審査なしで反映される）。
// 使い方: node scripts/asc/set-promotional-text.mjs <versionString> <locale> "<text>"
import { asc } from "./asc-lib.mjs";

const APP_ID = "6760606408";
const [versionString, locale, text] = process.argv.slice(2);
if (!versionString || !locale || !text) {
  console.error('usage: node scripts/asc/set-promotional-text.mjs 1.2.1 ja "..."');
  process.exit(1);
}
if (text.length > 170) throw new Error(`promotional text is ${text.length} chars (max 170)`);

const versions = await asc(`/v1/apps/${APP_ID}/appStoreVersions?filter[versionString]=${versionString}`);
const version = versions.data[0];
if (!version) throw new Error(`version ${versionString} not found`);
const locs = await asc(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`);
const loc = locs.data.find((l) => l.attributes.locale === locale);
if (!loc) throw new Error(`locale ${locale} not found on ${versionString}`);

await asc(`/v1/appStoreVersionLocalizations/${loc.id}`, {
  method: "PATCH",
  body: { data: { type: "appStoreVersionLocalizations", id: loc.id, attributes: { promotionalText: text } } },
});
const check = await asc(`/v1/appStoreVersionLocalizations/${loc.id}`);
console.log(`✓ ${versionString} ${locale} promotionalText = ${check.data.attributes.promotionalText}`);
