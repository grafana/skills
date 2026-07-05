# Datasource Plugins: setConfigEditor, setQueryEditor, and Support Editors

Datasource plugins (type: `"datasource"`) apply the same lazy-loading pattern to `setConfigEditor()`,
`setQueryEditor()`, and the `editor`/`QueryEditor` fields on `VariableSupport` and `AnnotationSupport`.
Rename `module.ts` → `module.tsx` and lazy-load all four:

```tsx
// src/module.tsx (datasource plugin)
import React, { Suspense } from 'react';
import { DataSourcePlugin } from '@grafana/data';
import { DataSource, DSOptions } from './datasource';
import { Query } from './types';
import type { KGQueryEditorProps } from './components/QueryEditor';

// Named exports → re-map to default with .then()
const LazyConfigEditor = React.lazy(() =>
  import('./components/ConfigEditor').then(m => ({ default: m.ConfigEditor }))
);
const LazyQueryEditor = React.lazy(() =>
  import('./components/QueryEditor').then(m => ({ default: m.QueryEditor }))
);

function ConfigEditor(props: DataSourcePluginOptionsEditorProps<DSOptions>) {
  return <Suspense fallback={null}><LazyConfigEditor {...props} /></Suspense>;
}
function QueryEditor(props: KGQueryEditorProps) {
  return <Suspense fallback={null}><LazyQueryEditor {...props} /></Suspense>;
}

export const plugin = new DataSourcePlugin<DataSource, Query, DSOptions>(DataSource)
  .setConfigEditor(ConfigEditor)
  .setQueryEditor(QueryEditor);
```

## VariableSupport and AnnotationSupport

For `VariableSupport` and `AnnotationSupport`, rename the `.ts` file to `.tsx` and assign the
lazy-wrapped component:

```tsx
// src/datasource/VariableSupport.tsx (renamed from .ts)
import React, { Suspense } from 'react';
import type { VariableQueryEditorProps } from './components/VariableQueryEditor';

const LazyVariableQueryEditor = React.lazy(() =>
  import('./components/VariableQueryEditor').then(m => ({ default: m.VariableQueryEditor }))
);
function VariableQueryEditorWithSuspense(props: VariableQueryEditorProps) {
  return <Suspense fallback={null}><LazyVariableQueryEditor {...props} /></Suspense>;
}

export class MyVariableSupport extends CustomVariableSupport<DataSource, MyVariableQuery> {
  editor = VariableQueryEditorWithSuspense;
  // ...
}
```

Apply the same pattern for `AnnotationSupport.QueryEditor`.

**Key rule:** Use `import type` for props interfaces — a regular import creates a real module dependency
that webpack follows, pulling the component code into the eager bundle and defeating the split.
