# Grafana Dashboards - Detailed Reference

## What is a Dashboard?

A Grafana dashboard is a set of one or more panels organized into rows, providing an at-a-glance view of related information. Dashboards connect to data sources, display data through panels, and support interactive filtering via variables.

## Core Components

- **Panels**: Containers that display visualizations; each combines a query + a visualization type
- **Rows**: Horizontal groupings of panels; can be collapsed for organization
- **Data Sources**: Connections to databases, APIs, or services that panels query
- **Variables**: Dropdown selectors at the top of a dashboard for dynamic filtering
- **Annotations**: Markers overlaid on graphs to indicate events

---

## Creating Dashboards

### From scratch
1. Click **Dashboards** in the left sidebar
2. Click **New > New dashboard**
3. Click **Add visualization** to add your first panel
4. Select a data source, write a query, choose visualization type
5. Click **Apply** to save the panel to the dashboard
6. Click the save icon (or Ctrl+S) to save the dashboard

### From a template / Import
- Click **Dashboards > New > Import**
- Paste a dashboard JSON, enter a Grafana.com dashboard ID, or upload a JSON file
- Grafana.com hosts thousands of community dashboards (grafana.com/grafana/dashboards)

---

## Dashboard Settings

Access via the gear icon at the top-right of any dashboard.

| Setting | Description |
|---------|-------------|
| General | Name, description, tags, folder, editable flag |
| Annotations | Configure annotation queries that overlay events on panels |
| Variables | Add/edit template variables (dropdowns at top) |
| Links | Add links to other dashboards or external URLs |
| JSON Model | View/edit raw JSON for the entire dashboard |
| Versions | Browse and restore prior versions |
| Time options | Default time range, auto-refresh intervals, timezone |

---

## Time Range Controls

- **Time picker** (top-right): Select absolute or relative ranges (Last 6 hours, Last 7 days, etc.)
- **Auto-refresh**: Set to Off, 5s, 10s, 30s, 1m, 5m, etc.
- **Zoom**: Click-drag on any time series to zoom in

### Common relative time shortcuts
```
now-5m    last 5 minutes
now-1h    last 1 hour
now-24h   last 24 hours
now-7d    last 7 days
now/d     today so far
now-1d/d  yesterday
```

---

## Annotations

Annotations are event markers overlaid on time series panels.

### Types
- **Native annotations**: Manually add a note to a specific time directly in the dashboard
- **Query annotations**: Pull events from a data source and display as markers

### Adding a manual annotation
- Hold Ctrl (or Cmd on Mac) and click a time series panel
- Type a description; optionally set a time range

---

## Library Panels

Library panels are reusable panel definitions shared across multiple dashboards.

- **Create**: Panel menu (3-dot) > "Create library panel"
- **Use**: Add a panel > "Add from panel library"
- **Update**: Edit the source panel; all dashboards using it reflect the change
- **Unlink**: Detach to make it independent in a specific dashboard

---

## Panel Layout

- Drag panel corners to resize
- Drag panel header to move
- **Add > Row** to insert collapsible rows
- Panel menu > **Duplicate** to clone within the same dashboard

---

## Dashboard Versions

- Access via Dashboard Settings > Versions
- See who saved what and when
- Compare two versions (diff view)
- Restore any previous version

---

## JSON Model

Every dashboard is stored as a JSON document.

Key top-level JSON fields:
```json
{
  "title": "My Dashboard",
  "uid": "abc123",
  "tags": ["production", "infrastructure"],
  "time": { "from": "now-6h", "to": "now" },
  "refresh": "30s",
  "panels": [],
  "templating": { "list": [] },
  "annotations": { "list": [] }
}
```

---

## Sharing Dashboards

### Share link
- Click **Share** icon > **Link** tab
- Toggle "Lock time range" to embed the current time window
- Toggle "Include template variable values"

### Snapshot
- **Share > Snapshot**: Creates a read-only, public snapshot
- Contains rendered data at share time - no live data source access needed
- Can expire (1 hour, 1 day, 7 days, or never)

### Export / Import JSON
- **Share > Export**: Download the dashboard JSON
- Import at **Dashboards > New > Import**
- Useful for version control, migration, sharing with the community

### Embed
- **Share > Embed**: Generates an iframe HTML snippet
- Requires anonymous access in Grafana config (OSS/Enterprise only)

### Public dashboards (Grafana 10+)
- Make a dashboard publicly accessible with no login
- Enable per-dashboard in Share > Public dashboard

---

## Playlists

Playlists cycle through dashboards automatically at a configurable interval.

- Create at **Dashboards > Playlists > New playlist**
- Add dashboards by name or tag
- Set interval (e.g., 5 minutes)
- Append `?kiosk=1` to URL for kiosk/TV mode

---

## Best Practices

1. **Organize with folders**: Use folders as RBAC permission boundaries
2. **Use variables**: Make dashboards reusable across environments/services
3. **Limit panels per dashboard**: Aim for <20 panels for performance
4. **Use library panels**: Standardize common panels across teams
5. **Tag dashboards**: Consistent tags for searchability
6. **Version control**: Export JSON and store in Git
7. **Use rows**: Collapse related panels to organize complex dashboards
8. **Template your queries**: Use variables so one dashboard covers many targets

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Ctrl+S` | Save dashboard |
| `e` | Open panel editor (when panel focused) |
| `v` | Toggle panel fullscreen |
| `d r` | Refresh all panels |
| `d s` | Dashboard settings |
| `d k` | Toggle kiosk mode |
| `?` | Show all shortcuts |

---

## Provisioning Dashboards (as Code)

```yaml
# /etc/grafana/provisioning/dashboards/default.yaml
apiVersion: 1

providers:
  - name: default
    orgId: 1
    folder: Infrastructure
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: false
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
```

Place dashboard JSON files in `/var/lib/grafana/dashboards/`. Subdirectories become folders when `foldersFromFilesStructure: true`.
