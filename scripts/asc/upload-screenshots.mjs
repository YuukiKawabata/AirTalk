// ストア用スクショ（docs/screenshots/.../store/<device>/*.png）を App Store Connect に上げる。
// 指定したバージョン・言語の既存スクショは削除してから、ファイル名順にアップロードする。
// 使い方: node scripts/asc/upload-screenshots.mjs <versionString> <locale> <storeDir>
//   例: node scripts/asc/upload-screenshots.mjs 1.3 ja docs/screenshots/store
//       node scripts/asc/upload-screenshots.mjs 1.3 en-US docs/screenshots/en/store
import { readFileSync, readdirSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import { basename, join } from "node:path";
import { asc } from "./asc-lib.mjs";

const APP_ID = "6760606408";
const DISPLAY_TYPES = { iphone: "APP_IPHONE_65", ipad: "APP_IPAD_PRO_3GEN_129" };

const [versionString, locale, storeDir] = process.argv.slice(2);
if (!versionString || !locale || !storeDir) {
  console.error("usage: node scripts/asc/upload-screenshots.mjs 1.3 ja docs/screenshots/store");
  process.exit(1);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const versions = await asc(`/v1/apps/${APP_ID}/appStoreVersions?filter[versionString]=${versionString}`);
const version = versions.data[0];
if (!version) throw new Error(`version ${versionString} not found`);
const locs = await asc(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`);
const loc = locs.data.find((l) => l.attributes.locale === locale);
if (!loc) throw new Error(`locale ${locale} not found on ${versionString}`);

const sets = await asc(`/v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets?include=appScreenshots&limit=50`);

async function uploadOne(setId, path) {
  const bytes = readFileSync(path);
  const reservation = await asc("/v1/appScreenshots", {
    method: "POST",
    body: {
      data: {
        type: "appScreenshots",
        attributes: { fileName: basename(path), fileSize: statSync(path).size },
        relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: setId } } },
      },
    },
  });
  const shot = reservation.data;
  for (const op of shot.attributes.uploadOperations) {
    const headers = Object.fromEntries(op.requestHeaders.map((h) => [h.name, h.value]));
    const res = await fetch(op.url, {
      method: op.method,
      headers,
      body: bytes.subarray(op.offset, op.offset + op.length),
    });
    if (!res.ok) throw new Error(`chunk upload failed: ${res.status}`);
  }
  await asc(`/v1/appScreenshots/${shot.id}`, {
    method: "PATCH",
    body: {
      data: {
        type: "appScreenshots",
        id: shot.id,
        attributes: { uploaded: true, sourceFileChecksum: createHash("md5").update(bytes).digest("hex") },
      },
    },
  });
  for (let i = 0; i < 30; i++) {
    const state = (await asc(`/v1/appScreenshots/${shot.id}`)).data.attributes.assetDeliveryState?.state;
    if (state === "COMPLETE") return;
    if (state === "FAILED") throw new Error(`processing failed: ${path}`);
    await sleep(2000);
  }
  throw new Error(`processing timed out: ${path}`);
}

for (const [device, displayType] of Object.entries(DISPLAY_TYPES)) {
  const dir = join(storeDir, device);
  const files = readdirSync(dir).filter((f) => f.endsWith(".png")).sort().map((f) => join(dir, f));
  if (files.length === 0) throw new Error(`no screenshots in ${dir}`);

  let set = sets.data.find((s) => s.attributes.screenshotDisplayType === displayType);
  if (set) {
    for (const s of set.relationships.appScreenshots.data) {
      await asc(`/v1/appScreenshots/${s.id}`, { method: "DELETE" });
    }
  } else {
    set = (await asc("/v1/appScreenshotSets", {
      method: "POST",
      body: {
        data: {
          type: "appScreenshotSets",
          attributes: { screenshotDisplayType: displayType },
          relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: loc.id } } },
        },
      },
    })).data;
  }

  for (const f of files) await uploadOne(set.id, f);
  console.log(`✓ ${versionString} ${locale} ${displayType}: ${files.map((f) => basename(f)).join(", ")}`);
}
