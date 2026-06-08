// k6-browser functional test for workflow <WORKFLOW_PLACEHOLDER>.
//
// Hand-converted from recordings/scripts/<WORKFLOW_PLACEHOLDER>.js per the
// k6-perf-test-website skill's 5-step procedure in functional-tests.md. The
// page-interaction body is structurally identical to the Playwright recorder;
// only the framework scaffolding differs.
//
// Run:
//   k6 run tests/<WORKFLOW_PLACEHOLDER>/browser.js
//   K6_BROWSER_HEADLESS=true k6 run tests/<WORKFLOW_PLACEHOLDER>/browser.js

import { browser } from 'k6/browser';
import { expect } from 'https://jslib.k6.io/k6-testing/0.5.0/index.js';

const BASE_URL = __ENV.BASE_URL || 'https://target-host.example';

export const options = {
  scenarios: {
    '<WORKFLOW_PLACEHOLDER>': {
      executor: 'shared-iterations',
      vus: 1,
      iterations: 1,
      options: { browser: { type: 'chromium' } },
    },
  },
};

export default async function () {
  // browser.newPage() is the default; iterations don't share cookies. If you
  // need a fresh browser context per iteration (e.g. to ensure logged-out
  // start state), see references/functional-tests.md for newContext().
  const page = await browser.newPage();

  try {
    // Step 1: open homepage. Wait for a post-hydration sentinel (an interactive
    // element that only exists after JS has hydrated). See the k6-perf-test-website
    // skill's recording-with-playwright.md.
    await page.goto(BASE_URL, { waitUntil: 'load' });

    // EXAMPLE -- the structural pattern is:
    //   1. Locate + wait for the post-hydration sentinel.
    //   2. Use `expect(...).toBeVisible()` to fail loudly if the sentinel
    //      doesn't appear.
    //   3. For timed actions, use `performance.mark()` / `performance.measure()`
    //      inside `page.evaluate()` and a custom Trend. Do NOT use `group()`
    //      around `await` -- in k6/browser's async runtime, `group()` does not
    //      wrap awaited code correctly and `group_duration` will not capture
    //      what you expect. See references/slo-design.md (the "async vs sync"
    //      section).
    //   4. Use Promise.all([waitForResponse, click]) so the response is captured
    //      before the next assertion.
    //   5. Assert the result element appears with expect(...).toBeVisible().
    //
    // Replace the body below with the actual workflow:

    // const primaryAction = page.locator('button[name="primary-action"]');
    // await primaryAction.waitFor({ state: 'visible' });
    // await expect(primaryAction).toBeVisible();
    //
    // // Mark the start of the timed action (NOT inside a group()).
    // await page.evaluate(() => performance.mark('action-start'));
    //
    // await Promise.all([
    //   page.waitForResponse(
    //     (r) => r.url().includes('/api/action') && r.request().method() === 'POST',
    //   ),
    //   primaryAction.click(),
    // ]);
    //
    // const result = page.locator('#result');
    // await result.waitFor({ state: 'visible' });
    // await expect(result).toBeVisible();
    //
    // // Read the duration back into a custom Trend in smoke.js / average.js etc.
    // // (In the bare functional browser.js you can skip this; the Trend lives in
    // // the load-test scripts where measurement matters.)

  } finally {
    // Always close the page in finally -- resource leak otherwise.
    await page.close();
  }
}
