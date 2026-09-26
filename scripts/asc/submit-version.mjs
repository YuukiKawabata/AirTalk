// バージョンにビルドを紐づけて審査に提出する。
// ビルドの処理が終わっていなければ待つ（最大 30 分）。--dry-run で状態の確認だけ行う。
// 使い方: node scripts/asc/submit-version.mjs <versionString> <buildNumber> [--dry-run]
import { asc } from "./asc-lib.mjs";

const APP_ID = "6760606408";
const [versionString, buildNumber, flag] = process.argv.slice(2);
const dryRun = flag === "--dry-run";
if (!versionString || !buildNumber) {
  console.error("usage: node scripts/asc/submit-version.mjs 1.3 9 [--dry-run]");
  process.exit(1);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ビルドの処理完了を待つ
let build;
for (let i = 0; i < 60; i++) {
  const builds = await asc(`/v1/builds?filter[app]=${APP_ID}&filter[version]=${buildNumber}&filter[preReleaseVersion.version]=${versionString}&limit=5`);
  build = builds.data[0];
  const state = build?.attributes.processingState ?? "NOT_FOUND";
  console.log(`build ${versionString}(${buildNumber}): ${state}`);
  if (state === "VALID") break;
  if (state === "INVALID" || state === "FAILED") throw new Error(`build processing ${state}`);
  if (dryRun) process.exit(0);
  await sleep(30000);
}
if (build?.attributes.processingState !== "VALID") throw new Error("build not ready in time");

// 輸出コンプライアンス（Info.plist で ITSAppUsesNonExemptEncryption=false 済み。未設定なら false にする）
if (build.attributes.usesNonExemptEncryption == null && !dryRun) {
  await asc(`/v1/builds/${build.id}`, {
    method: "PATCH",
    body: { data: { type: "builds", id: build.id, attributes: { usesNonExemptEncryption: false } } },
  });
}

const versions = await asc(`/v1/apps/${APP_ID}/appStoreVersions?filter[versionString]=${versionString}`);
const version = versions.data[0];
if (!version) throw new Error(`version ${versionString} not found`);
console.log(`version ${versionString}: ${version.attributes.appStoreState}`);
if (dryRun) process.exit(0);

// ビルドを紐づける
await asc(`/v1/appStoreVersions/${version.id}/relationships/build`, {
  method: "PATCH",
  body: { data: { type: "builds", id: build.id } },
});
console.log(`✓ attached build ${build.id}`);

// 審査に提出（未提出の reviewSubmission があれば再利用）
const existing = await asc(`/v1/reviewSubmissions?filter[app]=${APP_ID}&filter[state]=READY_FOR_REVIEW&limit=5`);
let submission = existing.data[0];
if (!submission) {
  submission = (await asc("/v1/reviewSubmissions", {
    method: "POST",
    body: {
      data: {
        type: "reviewSubmissions",
        attributes: { platform: "IOS" },
        relationships: { app: { data: { type: "apps", id: APP_ID } } },
      },
    },
  })).data;
}
const items = await asc(`/v1/reviewSubmissions/${submission.id}/items`);
const hasVersion = items.data.some((it) => it.relationships?.appStoreVersion?.data?.id === version.id);
if (!hasVersion) {
  await asc("/v1/reviewSubmissionItems", {
    method: "POST",
    body: {
      data: {
        type: "reviewSubmissionItems",
        relationships: {
          reviewSubmission: { data: { type: "reviewSubmissions", id: submission.id } },
          appStoreVersion: { data: { type: "appStoreVersions", id: version.id } },
        },
      },
    },
  });
}
await asc(`/v1/reviewSubmissions/${submission.id}`, {
  method: "PATCH",
  body: { data: { type: "reviewSubmissions", id: submission.id, attributes: { submitted: true } } },
});
const after = await asc(`/v1/reviewSubmissions/${submission.id}`);
console.log(`✓ submitted: reviewSubmission ${submission.id} (${after.data.attributes.state})`);
