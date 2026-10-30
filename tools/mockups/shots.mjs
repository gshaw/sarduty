// Mockup kit: shoot a round's pages from its shots.json. See docs/mockups.md.
//   node tools/mockups/shots.mjs <round> [page ...]
// Each shot is taken at 2x, cropped, then drawn inside its frame: a browser window with
// the page's URL, an iPhone, or nothing for pages that draw their own (phones of texts).
// Writes <folder>/shots/<page>.png and .jpg.
import { createRequire } from "module";
import { execFileSync } from "child_process";
import fs from "fs";
import path from "path";

const require = createRequire(import.meta.url);
const kit = path.dirname(new URL(import.meta.url).pathname);
// Installed once into tmp/puppeteer; see docs/mockups.md.
const puppeteer = require(process.env.PUPPETEER || path.join(kit, "../../tmp/puppeteer/node_modules/puppeteer-core"));
const dir = path.resolve(process.argv[2] || ".");
const only = process.argv.slice(3);
const { shots } = JSON.parse(fs.readFileSync(path.join(dir, "shots.json"), "utf8"));
fs.mkdirSync(path.join(dir, "shots"), { recursive: true });

const browser = await puppeteer.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" });
const page = await browser.newPage();

// Where to crop, in CSS pixels: "marks" ends below the last mark, "full" is the page,
// and { top, bottom } are selectors (top of the first match, bottom of the last).
async function cropBox(shot) {
  return page.evaluate((crop, pad) => {
    const full = document.documentElement.scrollHeight;
    const rects = sel => [...document.querySelectorAll(sel)].map(e => e.getBoundingClientRect());
    if (crop === "full") return { top: 0, bottom: full, full };
    if (crop === "marks") {
      const r = rects(".mk, .mk-note");
      const bottom = r.length ? Math.max(...r.map(x => x.bottom + scrollY)) + pad : full;
      return { top: 0, bottom: Math.min(full, Math.max(bottom, 420)), full };
    }
    const top = crop.top ? Math.max(0, Math.min(...rects(crop.top).map(x => x.top + scrollY)) - pad) : 0;
    const bottom = crop.bottom ? Math.max(...rects(crop.bottom).map(x => x.bottom + scrollY)) + pad : full;
    return { top, bottom: Math.min(full, bottom), full };
  }, shot.crop || "marks", shot.pad ?? 56);
}

function frameHtml(shot, raw, width, cut, cutTop) {
  const img = `<img src="file://${raw}" style="width:${width}px">`;
  const css = `<link rel="stylesheet" href="file://${kit}/mock.css">`;
  let body;
  if (shot.frame === "phone") {
    body = `<div class="phone${cut ? " cut" : ""}"><div class="phone-screen"><div class="phone-status"><span>9:41</span>` +
      `<span class="island"></span><span class="icons">5G <i class="batt"></i></span></div>${img}</div></div>`;
  } else {
    const [host, ...rest] = (shot.url || "sarduty.com").split("/");
    body = `<div class="browser${cut ? " cut" : ""}${cutTop ? " cut-top" : ""}" style="width:${width}px"><div class="browser-bar">` +
      `<span class="browser-dots"><i></i><i></i><i></i></span><span class="browser-url">${host}` +
      `<b>${rest.length ? "/" + rest.join("/") : ""}</b></span><span style="width:52px"></span></div><div class="browser-shot">${img}</div></div>`;
  }
  return `<!doctype html><html><head><meta charset="utf-8">${css}</head><body class="frame">` +
    `<div style="display:inline-block">${body}</div></body></html>`;
}

for (const shot of shots) {
  if (only.length && !only.includes(shot.page)) continue;
  const width = shot.width || (shot.frame === "phone" ? 390 : 1280);
  const out = path.join(dir, "shots", shot.out || shot.page);
  await page.setViewport({ width, height: 900, deviceScaleFactor: 2 });
  await page.goto(`file://${path.join(dir, shot.page + ".html")}`, { waitUntil: "load" });
  await page.evaluate(() => document.fonts.ready);

  if (shot.frame === "none") {
    const box = await page.evaluate(() => {
      const r = document.body.firstElementChild.getBoundingClientRect();
      return { width: Math.ceil(r.width + 64), height: Math.ceil(r.height + 64) };
    });
    await page.setViewport({ width: Math.max(width, box.width), height: box.height, deviceScaleFactor: 2 });
    await page.screenshot({ path: out + ".png", fullPage: true });
  } else {
    const { top, bottom, full } = await cropBox(shot);
    const raw = out + ".raw.png";
    await page.screenshot({ path: raw, clip: { x: 0, y: top, width, height: bottom - top }, captureBeyondViewport: true });
    const framePath = out + ".frame.html";
    fs.writeFileSync(framePath, frameHtml(shot, raw, width, bottom < full - 4, top > 0));
    await page.setViewport({ width: width + (shot.frame === "phone" ? 100 : 64), height: 100, deviceScaleFactor: 2 });
    await page.goto(`file://${framePath}`, { waitUntil: "load" });
    await page.screenshot({ path: out + ".png", fullPage: true });
    fs.rmSync(raw);
    fs.rmSync(framePath);
  }
  execFileSync("sips", ["-s", "format", "jpeg", "-s", "formatOptions", "82", out + ".png", "--out", out + ".jpg"], { stdio: "ignore" });
  console.log("shot", shot.page);
}
await browser.close();
