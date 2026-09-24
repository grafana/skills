// Ephemeral k6/browser EXPLORER — this is NOT the deliverable test.
//
// Purpose: drive the live target with the same Chromium engine that will run
// the final test, and dump verified candidate selectors so you can choose
// getBy* locators grounded in the REAL rendered DOM (not guesses).
//
// How to use it (replay-and-extend loop):
//   1. Copy this file to a UNIQUE temp path (never a fixed name — concurrent or
//      repeated runs share $TMPDIR and clobber each other):
//        EXPLORER="$(mktemp -d)/explore.js"; cp <skill-dir>/scripts/explore.template.js "$EXPLORER"
//      It must NOT land in the user's project — only the final test is saved there.
//   2. Run headless against the target:
//        K6_BROWSER_HEADLESS=true TARGET=<url> k6 run "$EXPLORER"
//   3. Read the EXPLORE_CANDIDATES line, pick the locator for the NEXT step,
//      and append it to the CONFIRMED ACTIONS block below.
//   4. Re-run. The dump now reflects the state AFTER your action — the frontier
//      has moved forward. Repeat until every step in the journey is resolved.
//   5. Need more than the candidate list? Re-run with DUMP_HTML=1 to also get
//      an HTML slice for the current state.
//
// Every locator you confirm here is copy-paste ready for the final test, and is
// already proven to exist + be actionable in k6/browser.
import { browser } from 'k6/browser';

export const options = {
  scenarios: {
    explore: { executor: 'shared-iterations', options: { browser: { type: 'chromium' } } },
  },
};

const TARGET = __ENV.TARGET;
if (!TARGET) {
  throw new Error('TARGET is not set. Run as: K6_BROWSER_HEADLESS=true TARGET=<url> k6 run explore.js');
}
const DUMP_HTML = __ENV.DUMP_HTML === '1';
// Post-action settle before dumping. Raise via SETTLE_MS=4000 for slow-hydrating
// SPAs instead of editing this file (keeps the replay loop edit-free except for
// CONFIRMED ACTIONS).
const SETTLE_MS = Number(__ENV.SETTLE_MS || 1500);

export default async function () {
  const page = await browser.newPage();
  try {
    // Prefer 'load' over 'networkidle': marketing/analytics-heavy sites never go
    // idle and 'networkidle' will time out (proven on real sites).
    await page.goto(TARGET, { waitUntil: 'load' });
    await dismissConsent(page);

    // ─── CONFIRMED ACTIONS (replay) ──────────────────────────────────────────
    // Append ONE line per already-verified step, in order. Use the exact
    // locators you confirmed on previous runs. Examples:
    //   await page.getByRole('button', { name: 'Pizza, Please!' }).click();
    //   await page.getByLabel('Username').fill(__ENV.TEST_USERNAME);
    //   await page.getByPlaceholder('Search').fill('k6');
    //   await page.getByPlaceholder('Search').press('Enter');  // no submit button
    // Locators auto-wait for actionability — do NOT add waitFor() before them.
    // ─────────────────────────────────────────────────────────────────────────

    await page.waitForTimeout(SETTLE_MS); // let the post-action frontier settle
    await dumpFrontier(page);
  } finally {
    await page.close();
  }
}

// Best-effort consent/cookie dismissal. Real sites (proven: grafana.com,
// thepihut.com, youtube.com) overlay a consent dialog that intercepts clicks.
// Clicking in-page by text is fast and avoids locator-timeout stalls.
// LIMIT: consent managers rendered inside an <iframe> or shadow DOM (common
// for OneTrust/Sourcepoint/Didomi) are out of reach of this sweep — if the
// banner persists, resolve it as an explicit step (explore.md troubleshooting).
async function dismissConsent(page) {
  await page.evaluate(() => {
    const rx = /^(accept( all)?( cookies)?|allow( all)?( cookies)?|i agree|i accept|agree|got it|ok)$/i;
    // Only click VISIBLE matches — a hidden "OK"/"Agree" (closed modal,
    // sr-only element) still fires handlers on a JS click and can mutate
    // state before the first dump.
    const visible = (el) => {
      const r = el.getBoundingClientRect();
      const s = getComputedStyle(el);
      return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none';
    };
    const nodes = [...document.querySelectorAll('button, [role="button"], a')];
    const btn = nodes.find(
      (e) => visible(e) && rx.test((e.textContent || '').replace(/\s+/g, ' ').trim()),
    );
    if (btn) btn.click();
  });
  await page.waitForTimeout(500);
}

async function dumpFrontier(page) {
  const url = page.url();
  const title = await page.title();
  const candidates = await page.evaluate(() => {
    const visible = (el) => {
      const r = el.getBoundingClientRect();
      const s = getComputedStyle(el);
      return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none';
    };
    const clean = (v) => (v || '').replace(/\s+/g, ' ').trim().slice(0, 60);
    // Emit each naming signal SEPARATELY so the agent maps it to the right
    // getBy* — text/aria-label → getByRole({name}), placeholder → getByPlaceholder,
    // label → getByLabel, testid → getByTestId. Never fold these into one field:
    // the HTML `name` attribute is NOT the accessible name and must not be used.
    const out = [];
    // Interactive elements to act on, PLUS headings/status regions which are
    // common assertion targets (e.g. an "Our recommendation:" heading or a
    // "Success" status). Static body text that is none of these won't appear —
    // use DUMP_HTML=1 to resolve those, or assert the literal text the user gave.
    const nodes = document.querySelectorAll(
      'a,button,input,select,textarea,h1,h2,h3,h4,[role],[data-testid],[data-test],[aria-label]',
    );
    for (const el of nodes) {
      if (!visible(el)) continue;
      const c = { tag: el.tagName.toLowerCase() };
      const type = el.getAttribute('type');
      if (type) c.type = type;
      const role = el.getAttribute('role');
      if (role) c.role = role;
      const text = clean(el.textContent);
      if (text) c.text = text;
      const aria = clean(el.getAttribute('aria-label'));
      if (aria) c.ariaLabel = aria;
      const ph = clean(el.getAttribute('placeholder'));
      if (ph) c.placeholder = ph;
      if (el.labels && el.labels.length) {
        const lbl = clean(el.labels[0].textContent);
        if (lbl) c.label = lbl;
      }
      // Button-like inputs (<input type="submit|button|reset">) take their
      // accessible name from `value`, not text content.
      if (el.tagName === 'INPUT' && /^(submit|button|reset)$/i.test(type || '')) {
        const val = clean(el.value);
        if (val) c.value = val;
      }
      // data-testid and data-test are DIFFERENT: getByTestId() matches only
      // data-testid. Emit them separately so the right locator is chosen —
      // data-test needs page.locator('[data-test="…"]').
      const testid = el.getAttribute('data-testid');
      if (testid) c.testid = testid;
      const dataTest = el.getAttribute('data-test');
      if (dataTest) c.dataTest = dataTest;
      // The HTML `name` attribute is NOT the accessible name, but it IS a stable
      // hook for a CSS attribute locator when nothing else applies.
      const nameAttr = el.getAttribute('name');
      if (nameAttr) c.nameAttr = nameAttr;
      // Keep anything with a usable naming signal, PLUS every visible form
      // control — a bare <input name="login"> with no label must still surface.
      const isFormControl = /^(input|select|textarea)$/.test(c.tag);
      if (c.text || c.ariaLabel || c.placeholder || c.label || c.value || c.testid || c.dataTest || isFormControl) {
        out.push(c);
      }
      // Cap generously — nav-heavy shells (sidebars, mega-menus) can push the
      // real content past a small limit. Raise further or filter by container
      // (see explore.md) if a dense app still buries what you need.
      if (out.length >= 120) break;
    }
    return out;
  });

  console.log('EXPLORE_URL ' + url);
  console.log('EXPLORE_TITLE ' + title);
  console.log('EXPLORE_CANDIDATES ' + JSON.stringify(candidates));
  if (DUMP_HTML) {
    // Dump the BODY markup, not the full document — the <head> of a real site
    // can be tens of KB and would otherwise fill the slice before any content.
    const bodyHtml = await page.evaluate(() =>
      document.body ? document.body.innerHTML : document.documentElement.outerHTML,
    );
    console.log('EXPLORE_HTML_LEN ' + bodyHtml.length);
    console.log('EXPLORE_HTML ' + bodyHtml.slice(0, 60000));
  }
}
