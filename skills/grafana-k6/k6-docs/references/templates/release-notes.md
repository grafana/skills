# Release Notes Template

```markdown
### `feature.name` [#PR](https://github.com/grafana/k6/pull/PR)

Introduction paragraph explaining what the feature is and why it matters.

Additional context about when to use it and what problem it solves.

The method supports [specific capabilities]:

\`\`\`javascript
import http from 'k6/http';

export default function () {
  // Example showing feature usage
  const response = http.get('https://quickpizza.grafana.com/');
}
\`\`\`

This complements existing [related features](links) by providing [specific benefit].
```

## Important Notes

- Release note examples do NOT require `<!-- md-k6:skip -->` markers
- All examples should be practical and runnable
- Lead with user value, not technical implementation details
- Use active voice and clear language
- Thank external contributors with their @username
