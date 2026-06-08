// Playwright recorder template -- one per workflow.
//
// Copy this file to recordings/scripts/wN-<short-name>.js, then:
//   1. Replace <WORKFLOW_PLACEHOLDER> with the workflow name (e.g. w1-checkout).
//   2. Update BASE_URL and the `isAllowedHost` allow-list to match the target.
//   3. Update the `urlFilter` regex to match the same hosts.
//   4. Replace the "USER ACTION SEQUENCE" block with the actual workflow steps.
//   5. Run: `node recordings/scripts/wN-<short-name>.js`
//
// Produces:
//   recordings/har/<WORKFLOW_PLACEHOLDER>.har
//
// See the k6-perf-test-website skill's recording-with-playwright.md for design
// notes (third-party filter rationale, hydration sentinels, UA selection).

const path = require('path');
const { chromium } = require('playwright');

// --- Configuration --------------------------------------------------------------

const BASE_URL = process.env.BASE_URL || 'https://target-host.example';
const HAR_PATH = path.resolve(__dirname, '..', 'har', '<WORKFLOW_PLACEHOLDER>.har');

// Real Chrome UA. The default headless UA contains "HeadlessChrome" which
// triggers bot-blocking on many production sites. Set this to a recent Chrome
// version's UA string.
const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';

// Hosts we want to keep in the HAR. Everything else is aborted at the network
// layer AND filtered out of the HAR. This excludes third-party RUM, error
// reporters, analytics, ads, etc.
function isAllowedHost(url) {
  try {
    const u = new URL(url);
    return u.hostname === 'target-host.example' || u.hostname === 'localhost';
  } catch {
    return false;
  }
}

// HAR write-time filter -- entries whose URL does not match this regex are
// silently dropped. Must allow-list the same hosts as isAllowedHost.
const HAR_URL_FILTER = /^https?:\/\/(target-host\.example|localhost)(:\d+)?\//;

// --- Recorder body --------------------------------------------------------------

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    userAgent: USER_AGENT,
    recordHar: {
      path: HAR_PATH,
      mode: 'full',
      content: 'embed',
      urlFilter: HAR_URL_FILTER,
    },
  });

  // Belt-and-braces: also abort third-party requests at the network layer so
  // they don't send traffic to third parties during recording (politeness +
  // avoid status:-1 entries in the HAR).
  await context.route('**', (route) => {
    if (isAllowedHost(route.request().url())) return route.continue();
    return route.abort();
  });

  const page = await context.newPage();

  // ============================================================================
  // USER ACTION SEQUENCE -- replace this whole block with the actual workflow.
  // ============================================================================
  //
  // Pattern:
  //   1. page.goto(BASE_URL) + waitFor a post-hydration sentinel (an interactive
  //      element that only exists after the SPA has booted).
  //   2. page.click / page.fill / etc. for each user action.
  //   3. Promise.all([page.waitForResponse(...), page.click(...)]) when an action
  //      triggers a critical API call -- ensures the HAR captures the response.
  //   4. waitFor the result locator after each significant action.
  //   5. waitForTimeout(500) at the end so trailing in-flight requests land in
  //      the HAR before context.close().

  // Step 1: open homepage. Wait for a post-hydration sentinel (an element that
  // only exists after JS has hydrated -- typically an interactive button/link
  // rendered by the framework, not the SSR).
  await page.goto(BASE_URL, { waitUntil: 'load' });

  // EXAMPLE -- replace with the actual sentinel for the workflow:
  // const primaryAction = page.locator('button[name="primary-action"]');
  // await primaryAction.waitFor({ state: 'visible' });

  // Step 2..N: the user actions.
  //
  // EXAMPLE:
  // await Promise.all([
  //   page.waitForResponse(
  //     (r) => r.url().includes('/api/action') && r.request().method() === 'POST',
  //   ),
  //   primaryAction.click(),
  // ]);
  // await page.locator('#result').waitFor({ state: 'visible' });

  // Final settle so any trailing in-flight requests (CSS background-image
  // fetches kicked off by the result render, etc.) land in the HAR.
  await page.waitForTimeout(500);

  // ============================================================================
  // END USER ACTION SEQUENCE
  // ============================================================================

  await context.close();
  await browser.close();
  // Playwright writes HAR on context.close(); print confirmation.
  // eslint-disable-next-line no-console
  console.log(`HAR written: ${HAR_PATH}`);
})().catch((err) => {
  // eslint-disable-next-line no-console
  console.error(err);
  process.exit(1);
});
