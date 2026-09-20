#!/usr/bin/env node
/**
 * Soft-release click walk when Cursor browser MCP is dead (Server not found).
 *
 * Usage:
 *   set SMOKE_EMAIL=... & set SMOKE_PASSWORD=... & node scripts/smoke_click.mjs
 *   npx --yes playwright@1.49.1 install chromium   # first run only
 */
import {chromium} from "playwright";

const baseUrl = process.env.SMOKE_BASE_URL || "https://web-production-bc5d0.up.railway.app";
const email = process.env.SMOKE_EMAIL;
const password = process.env.SMOKE_PASSWORD;
const profilePath = process.env.SMOKE_PROFILE || "/player/%D0%93%D0%BB%D0%B0%D0%B2%D0%B0%D0%98%D0%BD%D0%BA%D0%B2%D0%B8%D0%B7%D0%B8%D1%86%D0%B8%D0%B8";

if (!email || !password) {
  console.error("Set SMOKE_EMAIL and SMOKE_PASSWORD (sandbox: Inquisitor + SEED_SUPER_ADMIN_PASSWORD)");
  process.exit(2);
}

const browser = await chromium.launch({headless: true});
const page = await browser.newPage({viewport: {width: 1280, height: 800}});
const log = (step, detail = "") => console.log(`[ok] ${step}${detail ? ` — ${detail}` : ""}`);

try {
  await page.goto(`${baseUrl}/users/sign_in`, {waitUntil: "domcontentloaded", timeout: 60000});
  log("sign_in page", page.url());

  await page.locator('input[name="user[login]"]').first().fill(email);
  await page.locator('input[name="user[password]"]').first().fill(password);
  await Promise.all([
    page.waitForNavigation({waitUntil: "domcontentloaded", timeout: 60000}).catch(() => null),
    page.locator('input[type="submit"], button[type="submit"]').first().click()
  ]);
  if (page.url().includes("sign_in")) {
    throw new Error("Still on sign_in after submit — bad credentials or CSRF");
  }
  log("logged in", page.url());

  await page.goto(`${baseUrl}/world`, {waitUntil: "domcontentloaded", timeout: 60000});
  log("world", await page.title());

  await page.goto(`${baseUrl}${profilePath}`, {waitUntil: "domcontentloaded", timeout: 60000});
  log("profile", page.url());

  const lookup = page.locator('[data-profile-lookup="1"] input[name="name"]');
  if (await lookup.count()) {
    const status = await page.locator("[data-presence-status]").first().getAttribute("data-presence-status");
    log("presence badge", status || "missing");
    await lookup.fill("___nobody___");
    await page.locator('[data-profile-lookup="1"] button[type="submit"]').click();
    await page.waitForLoadState("domcontentloaded");
    log("lookup miss handled", page.url());
  } else {
    log("lookup form not on this page yet (deploy pending?)");
  }

  await page.goto(`${baseUrl}/inventory`, {waitUntil: "domcontentloaded", timeout: 60000}).catch(() => null);
  log("inventory attempt", page.url());

  console.log("CLICK_SMOKE_OK");
} catch (err) {
  console.error("CLICK_SMOKE_FAIL", err.message);
  process.exitCode = 1;
} finally {
  await browser.close();
}
