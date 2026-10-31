// Mockup kit: shoot a round's pages from its shots.json. See docs/mockups.md.
//   node tools/mockups/shots.mjs <round> [page ...]
// Each shot is taken at 2x, cropped, then drawn inside its frame: a browser window with
// the page's URL, an iPhone, a sheet for a diagram, or nothing for pages that draw their
// own (phones of texts). A shot with an `id` gets its label above the frame. Writes
// <folder>/shots/<page>.png, plus a .jpg when that is smaller, and shots/contact when
// shots.json says "contact": true. The smaller of the two is the one posted.
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
const { shots, contact } = JSON.parse(fs.readFileSync(path.join(dir, "shots.json"), "utf8"));
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

const css = `<link rel="stylesheet" href="file://${kit}/mock.css">`;
const esc = t => t.replace(/&/g, "&amp;").replace(/</g, "&lt;");
// A PNG's width in pixels, from its header.
const pngWidth = file => fs.readFileSync(file).readUInt32BE(16);

function frameHtml(shot, raw, width, cut, cutTop) {
  const img = `<img src="file://${raw}" style="width:${width}px">`;
  let body;
  if (shot.frame === "sheet") {
    body = `<div class="sheet">${img}</div>`;
  } else if (shot.frame === "phone") {
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

// Shoot a page of our own (a frame, a label, the contact sheet) at its natural size.
async function shootHtml(file, html, width, out) {
  fs.writeFileSync(file, html);
  await page.setViewport({ width, height: 100, deviceScaleFactor: 2 });
  await page.goto(`file://${file}`, { waitUntil: "load" });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: out, fullPage: true });
  fs.rmSync(file);
}

// The finished shot: its label above the framed picture, so the label travels with it.
async function label(shot, bare, out) {
  if (!shot.id) return fs.copyFileSync(bare, out);
  const w = pngWidth(bare) / 2;
  await shootHtml(out + ".label.html", `<!doctype html><html><head><meta charset="utf-8">${css}</head>` +
    `<body class="frame labelled"><div class="shot-label"><b>${esc(shot.id)}</b>${esc(shot.title)}</div>` +
    `<img src="file://${bare}" style="display:block;width:${w}px"></body></html>`, w, out);
}

// Every shot small, with its label, in one picture: the round at a glance.
async function contactSheet(done) {
  const tiles = done.map(({ shot, bare }) => {
    const phone = pngWidth(bare) < 1200;
    return `<figure class="${phone ? "narrow" : ""}"><figcaption>${shot.id ? `<b>${esc(shot.id)}</b>` : ""}` +
      `${esc(shot.title)}</figcaption><img src="file://${bare}"></figure>`;
  }).join("");
  const out = path.join(dir, "shots", "contact");
  await shootHtml(out + ".html", `<!doctype html><html><head><meta charset="utf-8">${css}</head>` +
    `<body class="frame"><div class="contact">${tiles}</div></body></html>`, 1280, out + ".png");
  console.log("shot contact", jpg(out));
}

// Flat UI is smaller and sharper as PNG; a page with photos or a map is smaller as JPG.
// Keep the JPG only when it wins, so body.py posts the smaller file.
function jpg(out) {
  execFileSync("sips", ["-s", "format", "jpeg", "-s", "formatOptions", "85", out + ".png", "--out", out + ".jpg"], { stdio: "ignore" });
  const [png, jpeg] = [".png", ".jpg"].map(ext => fs.statSync(out + ext).size);
  if (jpeg >= png) fs.rmSync(out + ".jpg");
  return Math.round(Math.min(png, jpeg) / 1024) + " KB";
}
const done = [];

for (const shot of shots) {
  if (only.length && !only.includes(shot.page)) continue;
  const width = shot.width || (shot.frame === "phone" ? 390 : 1280);
  const out = path.join(dir, "shots", shot.out || shot.page);
  await page.setViewport({ width, height: 900, deviceScaleFactor: 2 });
  await page.goto(`file://${path.join(dir, shot.page + ".html")}`, { waitUntil: "load" });
  await page.evaluate(() => document.fonts.ready);

  const bare = out + ".bare.png";
  if (shot.frame === "none") {
    const box = await page.evaluate(() => {
      const r = document.body.firstElementChild.getBoundingClientRect();
      return { width: Math.ceil(r.width + 64), height: Math.ceil(r.height + 64) };
    });
    await page.setViewport({ width: Math.max(width, box.width), height: box.height, deviceScaleFactor: 2 });
    await page.screenshot({ path: bare, fullPage: true });
  } else {
    // A sheet ends with its diagram, not with the window.
    const sheet = shot.frame === "sheet" ? { crop: { bottom: ".diagram" }, pad: 0 } : {};
    const { top, bottom, full } = await cropBox({ ...sheet, ...shot });
    const raw = out + ".raw.png";
    await page.screenshot({ path: raw, clip: { x: 0, y: top, width, height: bottom - top }, captureBeyondViewport: true });
    const pad = shot.frame === "phone" ? 100 : 64;
    await shootHtml(out + ".frame.html", frameHtml(shot, raw, width, bottom < full - 4, top > 0), width + pad, bare);
    fs.rmSync(raw);
  }
  await label(shot, bare, out + ".png");
  done.push({ shot, bare });
  console.log("shot", shot.page, jpg(out));
}
if (contact && !only.length) await contactSheet(done);
for (const { bare } of done) fs.rmSync(bare);
await browser.close();
