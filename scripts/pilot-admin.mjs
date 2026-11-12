// Operator commands for the invite-only AirTalk pilot. Node 22+.
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline/promises";

async function main() {
  const [action = "reports", accountID, ...extra] = process.argv.slice(2);
  const usage = "node scripts/pilot-admin.mjs reports | suspend <account UUID> | restore <account UUID>";
  if (action === "--help") return console.log(usage);
  const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
  const changesAccount = action === "suspend" || action === "restore";
  const operation = action === "restore" ? "利用停止解除" : "利用停止";
  if (extra.length || !((action === "reports" && !accountID) ||
      (changesAccount && uuid.test(accountID ?? "")))) throw new Error(usage);

  if (changesAccount) {
    if (!process.stdin.isTTY) throw new Error(`${operation}は対話端末で実行してください。`);
    const prompt = createInterface({ input: process.stdin, output: process.stdout });
    try {
      const answer = await prompt.question(`対象 ${accountID} に対して${operation}を実行します。対象IDを再入力してください: `);
      if (answer !== accountID) return console.log("中止しました。");
    } finally { prompt.close(); }
  }
  const file = join(homedir(), ".config/airtalk-pilot/pilot-secrets.json");
  const { ADMIN_TOKEN } = JSON.parse(await readFile(file, "utf8"));
  if (typeof ADMIN_TOKEN !== "string" || ADMIN_TOKEN.length < 32) throw new Error("管理用の資格情報を確認してください。");
  const response = await fetch("https://airtalk-online-pilot.yorozu-works.workers.dev/admin/" + action, {
    method: action === "reports" ? "GET" : "POST",
    headers: { Authorization: "Bearer " + ADMIN_TOKEN, "Content-Type": "application/json" },
    body: changesAccount ? JSON.stringify({ accountID }) : undefined,
    redirect: "error",
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`管理APIが HTTP ${response.status} を返しました。`);
  const result = await response.json();
  if (changesAccount) {
    if (result.ok !== true) throw new Error(`${operation}の結果を確認できません。`);
    return console.log(`${operation}済み: ${accountID}`);
  }
  const accounts = typeof result.accounts === "number" ? `登録者: ${result.accounts}人 / ` : "";
  console.log(`${accounts}保持中の通報: ${result.reports.length}件 / Apple認証の失効処理待ち: ${result.revocationsPending}件`);
  for (const report of result.reports) {
    console.log(JSON.stringify({ target: report.target, reason: report.reason, expiresAt: new Date(report.until).toISOString() }));
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
