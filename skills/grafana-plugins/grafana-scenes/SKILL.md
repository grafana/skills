---
name: grafana-scenes
license: Apache-2.0
description:
  Build Grafana plugin pages using the @grafana/scenes framework. Use this skill when creating
  new scene pages, adding panels/visualizations, setting up drilldown navigation, defining
  variables, configuring query runners, building table/timeseries/stat panels, or extending
  SceneObjectBase for custom scene objects. Triggers on any work involving SceneApp, SceneAppPage,
  EmbeddedScene, SceneQueryRunner, SceneDataTransformer, PanelBuilders, SceneFlexLayout,
  QueryVariable, or drilldown/tab configuration in Grafana plugins.
---

# @grafana/scenes Framework

Build reactive, data-driven Grafana plugin pages with declarative scene objects.

## Core Concepts

Scenes composes a tree of objects: `SceneApp` → `SceneAppPage` → `EmbeddedScene` → layouts → panels. Each node can own data (`$data`), variables (`$variables`), time ranges (`$timeRange`), and behaviors (`$behaviors`) that propagate down the tree.

## Quick Start: New Scene Page

### 1. Create the scene file

```typescript
// src/components/scenes/MyFeature/scene.tsx
import {
  EmbeddedScene, SceneFlexLayout, SceneFlexItem,
  SceneQueryRunner, SceneVariableSet, QueryVariable,
  PanelBuilders, VariableValueSelectors, SceneControlsSpacer,
} from '@grafana/scenes';

export function getMyFeatureScene(params: { datasource: DataSourceRef }) {
  const queryRunner = new SceneQueryRunner({
    datasource: params.datasource,
    queries: [{ refId: 'A', expr: 'up{cluster=~"$cluster"}', instant: true, format: 'table' }],
  });

  const panel = PanelBuilders.table()
    .setData(queryRunner)
    .setTitle('My Table')
    .build();

  return new EmbeddedScene({
    $variables: new SceneVariableSet({
      variables: [
        new QueryVariable({
          name: 'cluster',
          query: 'label_values(up, cluster)',
          datasource: params.datasource,
          isMulti: true, includeAll: true, defaultToAll: true,
        }),
      ],
    }),
    controls: [new VariableValueSelectors({}), new SceneControlsSpacer()],
    body: new SceneFlexLayout({
      direction: 'column',
      children: [new SceneFlexItem({ body: panel })],
    }),
  });
}
```

### 2. Create the page

```typescript
// src/components/scenes/MyFeature/MyFeature.tsx
import { SceneAppPage, SceneTimeRange } from '@grafana/scenes';

export function getMyFeaturePage(params) {
  return new SceneAppPage({
    title: 'My Feature',
    url: '/a/my-plugin-id/my-feature',
    routePath: 'my-feature/*',
    $timeRange: new SceneTimeRange({ from: 'now-1h', to: 'now' }),
    getScene: () => getMyFeatureScene(params),
    drilldowns: [],
  });
}
```

### 3. Register in SceneApp

Add the page to the `SceneApp` pages array in the root scene file.

## Key Patterns

### Drilldowns (click-through navigation)

```typescript
drilldowns: [{
  routePath: ':cluster/*',
  getPage: (match, parent) => new SceneAppPage({
    title: decodeURIComponent(match.params.cluster),
    url: `${parent.state.url}/${match.params.cluster}`,
    routePath: `${match.params.cluster}/*`,
    getScene: () => detailScene(decodeURIComponent(match.params.cluster)),
  }),
}]
```

### Tabs (sub-pages within a detail view)

Pass `tabs: [SceneAppPage, ...]` instead of `getScene` on a `SceneAppPage`. Each tab is itself a `SceneAppPage` with its own scene.

### Query with transformations

Wrap a `SceneQueryRunner` in `SceneDataTransformer` to apply Grafana transforms or custom RxJS operators:

```typescript
new SceneDataTransformer({
  $data: queryRunner,
  transformations: [
    { id: 'organize', options: { renameByName: { 'Value #A': 'CPU' } } },
    (ctx) => (source) => source.pipe(map((frames) => /* custom transform */)),
  ],
})
```

### Custom scene object

Extend `SceneObjectBase` with a static `Component` for custom interactive UI:

```typescript
class MyWidget extends SceneObjectBase<MyWidgetState> {
  static Component = ({ model }: SceneComponentProps<MyWidget>) => {
    const state = model.useState();
    return <div>{state.value}</div>;
  };
}
```

### Table column overrides

Build `ConfigOverrideRule` objects for drill-down links, filtering, units, widths, custom cells.

### Panel types

`PanelBuilders.table()`, `.timeseries()`, `.stat()`, `.gauge()`, `.barchart()` — chain `.setData()`, `.setTitle()`, `.setUnit()`, `.setOption()`, `.setOverrides()`, then `.build()`.

## Common Pitfalls

- Always use `routePath: 'path/*'` (with wildcard) on pages that have drilldowns or tabs
- `encodeURIComponent`/`decodeURIComponent` URL params — K8s names can contain `/`
- Variables referenced in queries as `$varName` must exist in an ancestor `SceneVariableSet`
- `getScene` is called lazily; don't create side effects in the factory
- For instant queries, set both `instant: true` and `format: 'table'`

## Resources

- [@grafana/scenes Documentation](https://grafana.com/docs/grafana/latest/developers/plugins/create-plugin-ui/grafana-scenes/)
- [@grafana/scenes npm](https://www.npmjs.com/package/@grafana/scenes)
- [Grafana Plugin Tools](https://grafana.com/developers/plugin-tools/)
