// AirTalk 1.3 のストア用メタデータを App Store Connect に反映する（何度実行しても同じ結果になる）。
// 内容は docs/GROWTH_1.3.md の3章と同じ。
//   - バージョン 1.3 を作成（手動公開）
//   - 日本語: 名前・サブタイトル・キーワード・説明文・新機能・プロモーションテキスト
//   - 英語（en-US）: 同じ項目を新規追加
//   - 主要言語を en-US に変更
//   - AirTalk Plus の商品説明からアイスブレイクを外し、英語版を追加
//   - 審査メモが空なら 1.2.1 からコピー
// 使い方: node scripts/asc/apply-1.3-metadata.mjs
import { asc } from "./asc-lib.mjs";

const APP_ID = "6760606408";
const VERSION = "1.3";
const PRIVACY_URL = "https://yuukikawabata.github.io/airwish-support/";
const SUPPORT_URL = "https://yuukikawabata.github.io/airwish-support/";
const SUBSCRIPTION_GROUP_ID = "22193555";
const SUBSCRIPTIONS = {
  "6785129209": { en: "AirTalk Plus Monthly" },
  "6785129341": { en: "AirTalk Plus Yearly" },
};

const JA = {
  name: "AirTalks: オフライン近距離チャット",
  subtitle: "ネット不要・半径50mの一期一会トーク",
  keywords: "ブルートゥース,トランシーバー,すれ違い,圏外,機内モード,メッセンジャー,イベント,ローカル通信,近く,会話,友達,勉強会,プライバシー,無線,P2P,サーバーレス,旅行,フェス,キャンプ",
  promotionalText: "圏外でも、機内モードでも。Wi-FiとBluetoothで、半径50mにいる人とだけ話せるチャットです。アカウント登録は不要、会話は離れると自動で消えます。イベントや旅先での一期一会に。",
  inviteParagraph: "■ 近くに誰もいないときは\nQRコードを見せれば、友だちがその場でAirTalkを入れられます。",
  whatsNew: [
    "・初回起動時に使い方の説明を追加しました",
    "・近くに誰もいないとき、QRコードやリンクで友だちを誘えるようになりました",
    "・英語に対応しました",
    "・アイスブレイク（最初の一言の定型文）を無料で使えるようにしました",
    "・細かな表示を改善しました",
  ].join("\n"),
  subscriptionDescription: "Hostバッジ、プロフィールフレーム、プリセット、追加リアクション、プレミアムテーマを利用できます。",
};

const EN = {
  name: "AirTalks: Offline Nearby Chat",
  subtitle: "Bluetooth & Wi-Fi, no internet",
  keywords: "mesh,messenger,p2p,local,walkie,talkie,airplane,signal,festival,travel,event,proximity,wireless",
  promotionalText: "Chat with people within 50 m (160 ft), no internet or account needed. AirTalks connects over Wi-Fi and Bluetooth, and messages vanish when you move apart.",
  description: `AirTalks lets you chat with the people right around you, and only them.

No internet, no servers, no account. AirTalks uses Wi-Fi and Bluetooth to find people within about 50 m (160 ft) and connects you directly, one-on-one.

■ Conversations that don't last
Messages live only in your device's memory. When you move apart or close the app, every message is deleted automatically. No history is ever kept.

■ Offline and serverless
Messages travel directly from device to device, encrypted. Nothing goes through the internet, so it works where there's no signal, even in airplane mode with Wi-Fi and Bluetooth on.

■ Privacy first
No sign-up. No personal data is collected or sent. Your profile (nickname, icon, and status) is stored only on your device.

■ Great for
・Meetups, conferences, and festivals
・Cafés and coworking spaces
・Travel, hostels, and places with no signal

■ Nobody nearby? Invite a friend
Show a QR code and your friend can install AirTalks on the spot.

Say hi, chat, and let it go when you part ways.

Terms of Use (EULA): https://yuukikawabata.github.io/airwish-support/#terms
Privacy Policy: https://yuukikawabata.github.io/airwish-support/#privacy`,
  whatsNew: [
    "• Added a quick intro on first launch",
    "• Invite friends nearby with a QR code or link",
    "• Now available in English",
    "• Icebreakers are now free for everyone",
    "• Minor UI improvements",
  ].join("\n"),
  subscriptionDescription: "Host badge, profile frames, presets, reactions, themes",
};

const LIMITS = { name: 30, subtitle: 30, keywords: 100, promotionalText: 170, subscriptionDescription: 55 };
for (const [locale, t] of Object.entries({ ja: JA, en: EN })) {
  for (const [k, max] of Object.entries(LIMITS)) {
    if (t[k].length > max) throw new Error(`${locale}.${k} is ${t[k].length} chars (max ${max})`);
  }
}

const patch = (type, id, attributes) =>
  asc(`/v1/${type}/${id}`, { method: "PATCH", body: { data: { type, id, attributes } } });
const create = (type, attributes, relationships) =>
  asc(`/v1/${type}`, { method: "POST", body: { data: { type, attributes, relationships } } });
const rel = (name, type, id) => ({ [name]: { data: { type, id } } });

// --- バージョン 1.3 ---
let versions = await asc(`/v1/apps/${APP_ID}/appStoreVersions?limit=10`);
let version = versions.data.find((v) => v.attributes.versionString === VERSION);
if (!version) {
  const created = await create("appStoreVersions",
    { platform: "IOS", versionString: VERSION, releaseType: "MANUAL" },
    rel("app", "apps", APP_ID));
  version = created.data;
  console.log(`✓ created version ${VERSION} (${version.id})`);
} else {
  console.log(`• version ${VERSION} exists (${version.id}, ${version.attributes.appStoreState})`);
}

// --- appInfo（名前・サブタイトル） ---
const infos = await asc(`/v1/apps/${APP_ID}/appInfos`);
const info = infos.data.find((i) => (i.attributes.appStoreState ?? i.attributes.state) !== "READY_FOR_SALE") ?? infos.data[0];
console.log(`• appInfo ${info.id} (${info.attributes.appStoreState ?? info.attributes.state})`);
const infoLocs = await asc(`/v1/appInfos/${info.id}/appInfoLocalizations`);
for (const [locale, t] of [["ja", JA], ["en-US", EN]]) {
  const attrs = { name: t.name, subtitle: t.subtitle, privacyPolicyUrl: PRIVACY_URL };
  const loc = infoLocs.data.find((l) => l.attributes.locale === locale);
  if (loc) await patch("appInfoLocalizations", loc.id, attrs);
  else await create("appInfoLocalizations", { locale, ...attrs }, rel("appInfo", "appInfos", info.id));
  console.log(`✓ appInfo ${locale}: ${t.name} / ${t.subtitle}`);
}

// --- バージョンのローカライズ ---
const verLocs = await asc(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`);
const jaLoc = verLocs.data.find((l) => l.attributes.locale === "ja");
if (!jaLoc) throw new Error("ja localization missing on 1.3");
let jaDescription = jaLoc.attributes.description;
if (!jaDescription.includes("■ 近くに誰もいないときは")) {
  const anchor = "\n\n名乗って、話して";
  if (!jaDescription.includes(anchor)) throw new Error("ja description anchor not found");
  jaDescription = jaDescription.replace(anchor, `\n\n${JA.inviteParagraph}${anchor}`);
}
await patch("appStoreVersionLocalizations", jaLoc.id, {
  description: jaDescription, keywords: JA.keywords, whatsNew: JA.whatsNew, promotionalText: JA.promotionalText,
});
console.log("✓ version ja: description / keywords / whatsNew / promotionalText");

const enAttrs = {
  description: EN.description, keywords: EN.keywords, whatsNew: EN.whatsNew,
  promotionalText: EN.promotionalText, supportUrl: SUPPORT_URL,
};
const enLoc = verLocs.data.find((l) => l.attributes.locale === "en-US");
if (enLoc) await patch("appStoreVersionLocalizations", enLoc.id, enAttrs);
else await create("appStoreVersionLocalizations", { locale: "en-US", ...enAttrs }, rel("appStoreVersion", "appStoreVersions", version.id));
console.log("✓ version en-US: description / keywords / whatsNew / promotionalText");

// --- 主要言語 ---
const app = await asc(`/v1/apps/${APP_ID}`);
if (app.data.attributes.primaryLocale !== "en-US") {
  // 公開中のバージョン（英語ローカライズを追加できない）にも英語スクショが必要なため、
  // 1.3 が公開されるまでは 409 MISSING_SCREENSHOTS_PRIMARY_LOCALE になる。公開後にもう一度実行する。
  try {
    await patch("apps", APP_ID, { primaryLocale: "en-US" });
    console.log("✓ primaryLocale: ja → en-US");
  } catch (e) {
    const code = e.body?.errors?.[0]?.code ?? "";
    if (!code.includes("MISSING_SCREENSHOTS_PRIMARY_LOCALE")) throw e;
    console.log("… primaryLocale: 1.3 公開後に再実行して変更する（公開中バージョンに英語スクショが無いため）");
  }
} else {
  console.log("• primaryLocale already en-US");
}

// --- 審査メモ ---
let reviewDetail = null;
try { reviewDetail = (await asc(`/v1/appStoreVersions/${version.id}/appStoreReviewDetail`)).data; } catch (e) { if (e.status !== 404) throw e; }
if (!reviewDetail || !reviewDetail.attributes.notes) {
  const prev = versions.data.find((v) => v.attributes.versionString === "1.2.1");
  const src = (await asc(`/v1/appStoreVersions/${prev.id}/appStoreReviewDetail`)).data.attributes;
  const attrs = {
    contactFirstName: src.contactFirstName, contactLastName: src.contactLastName,
    contactPhone: src.contactPhone, contactEmail: src.contactEmail,
    demoAccountRequired: false, notes: src.notes,
  };
  if (reviewDetail) await patch("appStoreReviewDetails", reviewDetail.id, attrs);
  else await create("appStoreReviewDetails", attrs, rel("appStoreVersion", "appStoreVersions", version.id));
  console.log("✓ review notes copied from 1.2.1");
} else {
  console.log("• review notes present");
}

// --- AirTalk Plus ---
for (const [subId, names] of Object.entries(SUBSCRIPTIONS)) {
  const locs = await asc(`/v1/subscriptions/${subId}/subscriptionLocalizations`);
  // 承認済みのものは編集できない。英語を追加すると編集用の下書き（PREPARE_FOR_SUBMISSION）ができるので、そちらを直す
  const jaLocs = locs.data.filter((l) => l.attributes.locale === "ja");
  const ja = jaLocs.find((l) => !["APPROVED", "ACTIVE"].includes(l.attributes.state)) ?? jaLocs[0];
  // 承認済み（ACTIVE）のローカライズは API から編集できない（409 UNMODIFIABLE）ので、その場合は報告だけする
  const tryWrite = async (label, fn) => {
    try { await fn(); console.log(`✓ subscription ${subId}: ${label}`); }
    catch (e) {
      const code = e.body?.errors?.[0]?.code ?? "";
      if (!code.includes("UNMODIFIABLE") && e.status !== 409) throw e;
      console.log(`… subscription ${subId}: ${label} は API から変更できない（${e.body?.errors?.[0]?.detail ?? code}）`);
    }
  };
  if (ja && ja.attributes.description !== JA.subscriptionDescription) {
    await tryWrite("ja description", () => patch("subscriptionLocalizations", ja.id, { description: JA.subscriptionDescription }));
  }
  const en = locs.data.find((l) => l.attributes.locale === "en-US");
  const enSub = { name: names.en, description: EN.subscriptionDescription };
  await tryWrite(`en-US ${names.en}`, () => en
    ? patch("subscriptionLocalizations", en.id, enSub)
    : create("subscriptionLocalizations", { locale: "en-US", ...enSub }, rel("subscription", "subscriptions", subId)));
}
const groupLocs = await asc(`/v1/subscriptionGroups/${SUBSCRIPTION_GROUP_ID}/subscriptionGroupLocalizations`);
if (!groupLocs.data.find((l) => l.attributes.locale === "en-US")) {
  await create("subscriptionGroupLocalizations", { locale: "en-US", name: "AirTalk Plus", customAppName: "AirTalk" },
    rel("subscriptionGroup", "subscriptionGroups", SUBSCRIPTION_GROUP_ID));
  console.log("✓ subscription group en-US");
} else {
  console.log("• subscription group en-US exists");
}

console.log(`\nversion id: ${version.id}`);
