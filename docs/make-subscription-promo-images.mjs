// AirTalk Plus のプロモーション画像（App Store のアプリ内課金用 1024×1024）を生成する。
//
// ガイドライン 2.3.2 で「アプリのスクリーンショットをプロモーション画像に使っている」と
// 却下されたため、UI を一切含まない独自のアートワークを SVG で描き、Chrome のヘッドレス
// モードで PNG に書き出してから JPEG（アルファなし）に変換する。
// 月額・年額で配色とラベルを変え、どちらの商品の画像かが分かるようにしている。
//
// 使い方: node docs/make-subscription-promo-images.mjs
//   Chrome の場所は自動検出（CHROME=/path/to/chrome で上書き可）。
//   JPEG 変換は macOS なら sips、それ以外は Python の Pillow を使う。
// 出力: docs/screenshots/promo/airtalk-plus-{monthly,yearly}.{svg,jpg}
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const OUT_DIR = join(dirname(fileURLToPath(import.meta.url)), "screenshots", "promo");
const SIZE = 1024;

const variants = [
  {
    id: "monthly",
    label: "MONTHLY",
    bg: ["#1B0B3F", "#35137A", "#0D1C52"],
    glowA: "#8B5CFF",
    glowB: "#2FC6FF",
    frame: ["#5CE1FF", "#8B5CFF", "#FF6FD8"],
    avatar: "#6D3FE0",
  },
  {
    id: "yearly",
    label: "YEARLY",
    bg: ["#0B1030", "#1E1A5C", "#3A1150"],
    glowA: "#FFB347",
    glowB: "#C64DFF",
    frame: ["#FFE58A", "#FFB347", "#FF6F61"],
    avatar: "#5B2DB0",
  },
];

const FONT = `-apple-system, 'SF Pro Display', 'Helvetica Neue', Helvetica, Arial, 'Liberation Sans', sans-serif`;
const CX = 512;
const CY = 420;

// 4 方向に尖ったきらめき
function sparkle(x, y, r, opacity) {
  const k = r * 0.28;
  return `<path d="M${x} ${y - r} Q${x + k} ${y - k} ${x + r} ${y} Q${x + k} ${y + k} ${x} ${y + r} Q${x - k} ${y + k} ${x - r} ${y} Q${x - k} ${y - k} ${x} ${y - r}Z" fill="#FFFFFF" opacity="${opacity}"/>`;
}

function svg(v) {
  const rings = [170, 250, 330, 410]
    .map((r, i) => `<circle cx="${CX}" cy="${CY}" r="${r}" fill="none" stroke="#FFFFFF" stroke-opacity="${0.16 - i * 0.03}" stroke-width="2"${i === 1 ? ' stroke-dasharray="4 14" stroke-linecap="round"' : ""}/>`)
    .join("\n    ");

  // レーダー上の「近くにいる人」
  const peers = [
    [250, 170], [-60, 250], [200, 330], [150, 410], [-150, 330], [20, 410],
  ]
    .map(([deg, r]) => {
      const a = (deg * Math.PI) / 180;
      return `<circle cx="${(CX + r * Math.cos(a)).toFixed(1)}" cy="${(CY + r * Math.sin(a)).toFixed(1)}" r="9" fill="#FFFFFF" opacity="0.35"/>`;
    })
    .join("\n    ");

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${v.bg[0]}"/>
      <stop offset="0.55" stop-color="${v.bg[1]}"/>
      <stop offset="1" stop-color="${v.bg[2]}"/>
    </linearGradient>
    <radialGradient id="glowA"><stop offset="0" stop-color="${v.glowA}" stop-opacity="0.75"/><stop offset="1" stop-color="${v.glowA}" stop-opacity="0"/></radialGradient>
    <radialGradient id="glowB"><stop offset="0" stop-color="${v.glowB}" stop-opacity="0.55"/><stop offset="1" stop-color="${v.glowB}" stop-opacity="0"/></radialGradient>
    <linearGradient id="frame" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${v.frame[0]}"/>
      <stop offset="0.5" stop-color="${v.frame[1]}"/>
      <stop offset="1" stop-color="${v.frame[2]}"/>
    </linearGradient>
    <linearGradient id="face" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#E9E2FF"/>
    </linearGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFE9A3"/>
      <stop offset="1" stop-color="#FFB627"/>
    </linearGradient>
    <filter id="blur" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="18"/></filter>
    <filter id="shadow" x="-60%" y="-80%" width="220%" height="280%"><feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000000" flood-opacity="0.35"/></filter>
    <clipPath id="avatarClip"><circle cx="${CX}" cy="${CY}" r="112"/></clipPath>
  </defs>

  <rect width="${SIZE}" height="${SIZE}" fill="url(#bg)"/>
  <circle cx="300" cy="260" r="420" fill="url(#glowA)"/>
  <circle cx="820" cy="760" r="420" fill="url(#glowB)"/>

  <g>
    ${rings}
    ${peers}
  </g>

  <!-- プレミアムフレーム付きのプロフィール -->
  <circle cx="${CX}" cy="${CY}" r="136" fill="none" stroke="url(#frame)" stroke-width="26" filter="url(#blur)" opacity="0.9"/>
  <circle cx="${CX}" cy="${CY}" r="128" fill="url(#face)" filter="url(#shadow)"/>
  <circle cx="${CX}" cy="${CY}" r="128" fill="none" stroke="url(#frame)" stroke-width="16"/>
  <g clip-path="url(#avatarClip)">
    <circle cx="${CX}" cy="${CY - 26}" r="42" fill="${v.avatar}"/>
    <ellipse cx="${CX}" cy="${CY + 96}" rx="86" ry="70" fill="${v.avatar}"/>
  </g>

  <!-- Host バッジ -->
  <g filter="url(#shadow)" transform="translate(588 262) rotate(8)">
    <rect x="0" y="0" width="176" height="62" rx="31" fill="url(#gold)"/>
    <path d="M36 14 L42.5 27 L57 29 L46.5 39 L49 53 L36 46.3 L23 53 L25.5 39 L15 29 L29.5 27 Z" fill="#5A3A00"/>
    <text x="68" y="44" font-family="${FONT}" font-size="30" font-weight="800" letter-spacing="2" fill="#5A3A00">HOST</text>
  </g>

  <!-- テーマカラー -->
  <g filter="url(#shadow)">
    <circle cx="232" cy="292" r="30" fill="#FF9F43"/>
    <circle cx="272" cy="292" r="30" fill="#FF5FA2"/>
    <circle cx="312" cy="292" r="30" fill="#2ED3B7"/>
  </g>

  <!-- リアクション（吹き出し） -->
  <g filter="url(#shadow)" transform="translate(176 470)">
    <path d="M0 34 Q0 0 34 0 H130 Q164 0 164 34 V66 Q164 100 130 100 H58 L28 126 L34 100 Q0 100 0 66 Z" fill="#FFFFFF"/>
    <circle cx="52" cy="50" r="10" fill="${v.avatar}"/>
    <circle cx="82" cy="50" r="10" fill="${v.avatar}" opacity="0.7"/>
    <circle cx="112" cy="50" r="10" fill="${v.avatar}" opacity="0.45"/>
  </g>

  <!-- プロフィールプリセット（重なったカード） -->
  <g filter="url(#shadow)" transform="translate(716 478)">
    <rect x="28" y="-16" width="132" height="92" rx="20" fill="#FFFFFF" opacity="0.45" transform="rotate(10 94 30)"/>
    <rect x="14" y="-6" width="132" height="92" rx="20" fill="#FFFFFF" opacity="0.7" transform="rotate(4 80 40)"/>
    <rect x="0" y="4" width="132" height="92" rx="20" fill="#FFFFFF"/>
    <circle cx="34" cy="38" r="16" fill="url(#frame)"/>
    <rect x="60" y="28" width="52" height="10" rx="5" fill="#CFC6EA"/>
    <rect x="60" y="46" width="36" height="10" rx="5" fill="#E3DDF5"/>
    <rect x="20" y="68" width="92" height="10" rx="5" fill="#E3DDF5"/>
  </g>

  ${sparkle(752, 214, 22, 0.95)}
  ${sparkle(812, 290, 12, 0.7)}
  ${sparkle(198, 404, 14, 0.75)}
  ${sparkle(640, 640, 16, 0.8)}
  ${sparkle(372, 610, 10, 0.6)}

  <text x="${CX}" y="800" text-anchor="middle" font-family="${FONT}" font-size="104" font-weight="800" letter-spacing="-2" fill="#FFFFFF">AirTalk <tspan fill="url(#frame)">Plus</tspan></text>
  <rect x="${CX - 120}" y="842" width="240" height="60" rx="30" fill="#FFFFFF" fill-opacity="0.12" stroke="#FFFFFF" stroke-opacity="0.45" stroke-width="2"/>
  <text x="${CX}" y="883" text-anchor="middle" font-family="${FONT}" font-size="28" font-weight="700" letter-spacing="6" fill="#FFFFFF">${v.label}</text>
</svg>
`;
}

function findChrome() {
  if (process.env.CHROME) return process.env.CHROME;
  const candidates = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
  ];
  const pw = "/opt/pw-browsers";
  if (existsSync(pw)) {
    for (const dir of readdirSync(pw).filter((d) => d.startsWith("chromium-"))) {
      candidates.push(join(pw, dir, "chrome-linux", "chrome"));
    }
  }
  const found = candidates.find((p) => existsSync(p));
  if (!found) throw new Error("Chrome が見つかりません。CHROME=/path/to/chrome を指定してください");
  return found;
}

function toJpeg(png, jpg) {
  if (process.platform === "darwin") {
    execFileSync("sips", ["-c", String(SIZE), String(SIZE), "--cropOffset", "0", "0", png], { stdio: "ignore" });
    execFileSync("sips", ["-s", "format", "jpeg", "-s", "formatOptions", "95", png, "--out", jpg], { stdio: "ignore" });
  } else {
    execFileSync("python3", [
      "-c",
      "import sys; from PIL import Image; n=int(sys.argv[3]); Image.open(sys.argv[1]).crop((0, 0, n, n)).convert('RGB').save(sys.argv[2], quality=95)",
      png,
      jpg,
      String(SIZE),
    ]);
  }
}

mkdirSync(OUT_DIR, { recursive: true });
const chrome = findChrome();

for (const v of variants) {
  const svgPath = join(OUT_DIR, `airtalk-plus-${v.id}.svg`);
  const pngPath = join(OUT_DIR, `airtalk-plus-${v.id}.png`);
  const jpgPath = join(OUT_DIR, `airtalk-plus-${v.id}.jpg`);
  writeFileSync(svgPath, svg(v));
  execFileSync(chrome, [
    "--headless",
    "--disable-gpu",
    "--no-sandbox",
    "--hide-scrollbars",
    "--force-device-scale-factor=1",
    // ヘッドレスでもウィンドウ枠の分だけ描画領域が縮むので、縦に余裕を持たせて後で切り抜く
    `--window-size=${SIZE},${SIZE + 400}`,
    `--screenshot=${pngPath}`,
    `file://${svgPath}`,
  ], { stdio: "ignore" });
  toJpeg(pngPath, jpgPath);
  rmSync(pngPath);
  console.log(jpgPath);
}
