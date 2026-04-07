# User Documentation Template

## Front Matter

```yaml
---
title: 'methodName(param[, options])'
description: 'Module: class.methodName(param[, options]) method'
---
```

## Content Structure

```markdown
# methodName(param[, options])

Brief description of what the method does and when to use it.

| Parameter       | Type   | Default | Description                             |
| --------------- | ------ | ------- | --------------------------------------- |
| param           | string | -       | Required. Description of the parameter. |
| options         | object | `null`  |                                         |
| options.timeout | number | `30000` | Maximum time in milliseconds.           |

### Returns

| Type                | Description                              |
| ------------------- | ---------------------------------------- |
| Promise<ReturnType> | A Promise that fulfills with the result. |

### Examples

#### Example Title

\`\`\`javascript
import http from 'k6/http';
import { check } from 'k6';

export default function () {
  // Example code here
}
\`\`\`

### Best practices

1. **Practice title**: Description of the practice.

### Related

- [Related method](link) - Brief description
```

## Browser Module Example Template

```javascript
import { browser } from 'k6/browser';
import { check } from 'k6';

export const options = {
  scenarios: {
    ui: {
      executor: 'shared-iterations',
      options: {
        browser: {
          type: 'chromium',
        },
      },
    },
  },
};

export default async function () {
  const page = await browser.newPage();

  try {
    // Example code here
  } finally {
    await page.close();
  }
}
```

## Cross-Linking Guidelines

Always add bidirectional links between related methods in the `### Related` section:

1. **Identify related methods**: Methods that work together, handle similar events, or serve complementary purposes
1. **Bidirectional links**: If page A links to page B, page B should link back to page A
1. **Sort alphabetically**: Always list related links in alphabetical order
1. **Group related changes**: When adding cross-links, commit all related files together
1. **Descriptive link text**: Include brief descriptions explaining the relationship

Example (properly sorted):
```markdown
### Related

- [page.on()](link) - Subscribe to page events
- [page.waitForEvent()](link) - Wait for page events with predicate functions
- [page.waitForLoadState()](link) - Wait for load states
- [page.waitForNavigation()](link) - Wait for navigation events
```

## Formatting Rules

1. **Numbered lists**: Always use `1.` for every item (Markdown auto-numbers):
   ```markdown
   <!-- CORRECT -->
   1. First item
   1. Second item
   1. Third item
   ```

1. **Punctuation**: Pay attention to comma placement in compound sentences

1. **Consistency**: Match the formatting style of existing documentation

## Code Validation

- All JavaScript snippets are validated by ESLint
- Use comments to control validation:
  - `<!-- md-k6:skip -->` - Skip snippet execution
  - `<!-- eslint-skip -->` - Skip ESLint validation
  - `<!-- md-k6:nofail -->` - Allow errors in execution
