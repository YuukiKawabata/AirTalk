// アーカイブ済みのビルドを App Store Connect にアップロードする。
//
// API キーにクラウド署名の権限が無いため、自動署名の export は失敗する
// （"Cloud signing permission error"）。そこで他アプリと同じく、
//   1. ASC API で配布証明書を含む App Store 用プロファイルを用意してインストール
//   2. 手元のキーチェーンの配布証明書で手動署名して IPA を export
//   3. altool で IPA をアップロード
// の順に行う。認証は ~/.appstoreconnect/asc.env の API キー。
//
// 使い方: node scripts/asc/upload-build.mjs build/AirTalk-1.3-9.xcarchive
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { asc } from "./asc-lib.mjs";

const BUNDLE_ID = "com.yuuki.AirTalk";
const TEAM_ID = "976WT2WW6X";
const PROFILE_PREFIX = "AirTalk App Store (manual)";

const archive = process.argv[2];
if (!archive) {
  console.error("usage: node scripts/asc/upload-build.mjs <path.xcarchive>");
  process.exit(1);
}

const env = {};
for (const line of readFileSync(join(homedir(), ".appstoreconnect", "asc.env"), "utf8").split("\n")) {
  const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.+?)\s*$/);
  if (m && !line.trimStart().startsWith("#")) env[m[1]] = m[2];
}

function run(cmd, args) {
  const r = spawnSync(cmd, args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  return { status: r.status, out: `${r.stdout}\n${r.stderr}` };
}

// 1. プロファイル
async function ensureProfile() {
  const bundles = await asc(`/v1/bundleIds?filter[identifier]=${BUNDLE_ID}&limit=5`);
  const bundle = bundles.data.find((b) => b.attributes.identifier === BUNDLE_ID);
  if (!bundle) throw new Error(`bundleId ${BUNDLE_ID} not found`);

  const certs = await asc(`/v1/certificates?filter[certificateType]=IOS_DISTRIBUTION,DISTRIBUTION&limit=20`);
  const now = Date.now();
  const certIds = certs.data
    .filter((c) => new Date(c.attributes.expirationDate).getTime() > now)
    .map((c) => c.id);
  if (certIds.length === 0) throw new Error("no valid distribution certificate");

  const profiles = await asc(`/v1/bundleIds/${bundle.id}/profiles?limit=50`);
  let profile = profiles.data.find((p) =>
    p.attributes.name.startsWith(PROFILE_PREFIX)
    && p.attributes.profileType === "IOS_APP_STORE"
    && p.attributes.profileState === "ACTIVE");

  if (!profile) {
    const stamp = new Date().toISOString().replace(/[-:T.Z]/g, "").slice(0, 12);
    const created = await asc("/v1/profiles", {
      method: "POST",
      body: {
        data: {
          type: "profiles",
          attributes: { name: `${PROFILE_PREFIX} ${stamp}`, profileType: "IOS_APP_STORE" },
          relationships: {
            bundleId: { data: { type: "bundleIds", id: bundle.id } },
            certificates: { data: certIds.map((id) => ({ type: "certificates", id })) },
          },
        },
      },
    });
    profile = created.data;
    console.log(`✓ created profile: ${profile.attributes.name}`);
  } else {
    console.log(`✓ reusing profile: ${profile.attributes.name}`);
  }

  const full = await asc(`/v1/profiles/${profile.id}`);
  const { uuid, profileContent } = full.data.attributes;
  const bytes = Buffer.from(profileContent, "base64");
  for (const dir of [
    join(homedir(), "Library/Developer/Xcode/UserData/Provisioning Profiles"),
    join(homedir(), "Library/MobileDevice/Provisioning Profiles"),
  ]) {
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, `${uuid}.mobileprovision`), bytes);
  }
  return uuid;
}

const profileUUID = await ensureProfile();

// 2. IPA を export（手動署名）
const exportPath = archive.replace(/\.xcarchive$/, "").replace(/AirTalk-/, "export-");
const optionsPath = join(dirname(archive), "ExportOptions-Manual.plist");
writeFileSync(optionsPath, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key><string>export</string>
  <key>method</key><string>app-store-connect</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>provisioningProfiles</key>
  <dict><key>${BUNDLE_ID}</key><string>${profileUUID}</string></dict>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>signingStyle</key><string>manual</string>
  <key>stripSwiftSymbols</key><true/>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
`);

const exp = run("xcodebuild", [
  "-exportArchive", "-archivePath", archive, "-exportPath", exportPath,
  "-exportOptionsPlist", optionsPath,
]);
if (exp.status !== 0) {
  console.log(exp.out.split("\n").filter((l) => /error|EXPORT/.test(l)).join("\n"));
  process.exit(exp.status ?? 1);
}
const ipa = readdirSync(exportPath).find((f) => f.endsWith(".ipa"));
if (!ipa) throw new Error(`no .ipa in ${exportPath}`);
const ipaPath = join(exportPath, ipa);
console.log(`✓ exported ${ipaPath}`);

// 3. altool でアップロード
const auth = ["--api-key", env.ASC_KEY_ID, "--api-issuer", env.ASC_ISSUER_ID, "--p8-file-path", env.ASC_KEY_PATH];
const up = run("xcrun", ["altool", "--upload-package", ipaPath, ...auth, "--output-format", "json"]);
console.log(up.out.split("\n").filter((l) => l.trim()).slice(-12).join("\n"));
process.exit(up.status ?? 1);
