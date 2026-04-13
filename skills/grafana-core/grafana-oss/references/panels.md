# Grafana Panels and Visualizations - Detailed Reference

## What is a Panel?

A panel is the basic building block of a Grafana dashboard. Each panel combines:
- A **query** (or multiple queries) to a data source
- A **visualization type** to display the data
- **Field configuration** (units, thresholds, color mappings)
- Optional **transformations** to reshape the data before display

---

## Panel Editor

Open the panel editor by clicking a panel's title > Edit, or clicking **Add visualization** for a new panel.

### Panel Editor Layout

**Top bar**: Back to dashboard, Discard changes, Save dashboard

**Center**: Visualization preview (live update as you configure)

**Toggle**: "Table view" - shows raw query results as a table for debugging

**Right sidebar tabs**:
1. **Query** - configure data sources and write queries
2. **Transform** - apply data transformations
3. **Alert** - create alert rules from this panel
4. Below tabs: visualization-specific options and field config

### Query Tab

- **Data source selector**: Choose which data source to query
- **Query editor**: Data-source-specific interface (PromQL for Prometheus, LogQL for Loki, SQL for databases)
- **Query options**:
  - Max data points: Limit data points fetched
  - Min interval: Minimum auto-calculated interval
  - Interval: Override the auto-calculated interval
  - Relative time: Override dashboard time range for this panel only
  - Time shift: Shift the time range (e.g., to compare to last week)
- **+ Query**: Add multiple queries (labeled A, B, C...)
- **Expression**: Add server-side math expressions combining query results

---

## Visualization Types

### Time Series (default)
Best for: Metrics over time, continuous data
- Renders as lines, points, or bars
- Supports multiple series
- Configurable line width, fill, point size
- Supports thresholds as colored background regions
- Supports annotations overlay
- **Graph styles**: Lines, Bars, Points; can mix per series
- **Stacking**: None, Normal, 100%
- **Axis**: Left Y, Right Y, hidden
- Default visualization - supports alerting

### Stat
Best for: Single important metric (KPI display)
- Shows one or more values as large text
- Supports sparkline background
- Color modes: value, background, none
- Can show last value, mean, sum, etc.
- Great for dashboards that need quick status overviews

### Bar Chart
Best for: Comparing categorical data
- Horizontal or vertical orientation
- Grouped or stacked
- Supports labels on bars

### Gauge
Best for: Showing a value relative to min/max range
- Circular gauge with arc
- Configurable thresholds set colors
- Shows current value prominently

### Bar Gauge
Best for: Multiple metrics as horizontal/vertical bars
- Useful for comparing many items
- Supports thresholds for color coding
- Modes: gradient, retro LCD, basic

### Table
Best for: Tabular data, multi-column metrics
- Supports sorting by column
- Column width customization
- Cell display modes: color text, color background, gradient gauge
- Pagination for large datasets
- Can embed sparklines in cells

### Heatmap
Best for: Distribution over time, histogram-over-time
- X axis: time; Y axis: buckets; Color: density/value
- Supports pre-bucketed data (Prometheus histogram) and raw values
- Tooltip shows exact bucket counts

### Histogram
Best for: Value distribution analysis
- Groups values into buckets
- Can combine multiple series
- Configurable bucket size

### Pie Chart
Best for: Proportional data, parts-of-whole
- Pie or donut style
- Labels: name, value, percentage

### Logs
Best for: Log data from Loki, Elasticsearch, etc.
- Displays raw log lines with timestamp
- Log level coloring (info/warn/error)
- Search/filter within results
- Deduplication and time wrapping
- Prettify JSON option

### Traces
Best for: Distributed tracing visualization (Tempo)
- Renders trace spans as a waterfall/Gantt chart
- Shows service name, operation, duration
- Click to drill into trace details

### Flame Graph
Best for: CPU profiling data (Pyroscope)
- Visualizes call stacks by CPU time
- Click to zoom into subtrees

### Node Graph
Best for: Service dependency maps, network topology
- Renders nodes and edges
- Node color/size configurable by metric

### Geomap
Best for: Geographic data visualization
- Layers: markers, heatmap, route
- Multiple base map options (OpenStreetMap, CARTO, etc.)
- Supports GeoJSON data

### Canvas
Best for: Custom layouts, process diagrams, status boards
- Drag-and-drop element placement
- Elements: text, metric value, rectangle, ellipse, icon, image, connections
- Dynamic data binding per element

### State Timeline
Best for: State changes over time (on/off, OK/warn/crit)
- Horizontal bands showing state duration
- Each series = one row
- Color per state value

### Status History
Best for: Periodic state checks over time
- Grid: Y=services, X=time buckets
- Color per state

### XY Chart
Best for: Correlation between two metrics
- Scatter plot
- X and Y axis from different fields
- Bubble size from a third field

### Candlestick
Best for: Financial OHLC data
- Open/High/Low/Close representation
- Volume bars

### Text
Best for: Documentation panels, headers
- Renders Markdown or HTML

### Alert List
Best for: Dashboard overview of current alert states

### Dashboard List
Best for: Navigation panels linking to other dashboards

---

## Field Configuration (Standard Options)

Available for most visualizations under the visualization options panel.

| Option | Description |
|--------|-------------|
| Unit | Display unit (bytes, seconds, %, requests/sec, etc.) |
| Min / Max | Override auto-detected min/max for scales |
| Decimals | Number of decimal places |
| Display name | Override the series/field name |
| Color scheme | Fixed, thresholds-based, palette, etc. |
| No value | Text to display when value is null |

### Thresholds
Define color-coded boundaries:
- **Absolute**: Fixed numeric values (e.g., >90 = red, >70 = yellow, else green)
- **Percentage**: Relative to min/max

Example threshold config:
```
Base (default): Green
70: Yellow (warn)
90: Red (crit)
```

### Value Mappings
Transform raw values into human-readable labels or colors:
- **Value to text**: e.g., `1` -> "OK", `0` -> "Down"
- **Range to text**: e.g., `0-50` -> "Low"
- **Regex to text**: Match patterns

### Data Links
Create clickable links from panel values:
- Link to other dashboards with variable values interpolated
- Link to external systems (e.g., Kibana, PagerDuty)
- Use `${__value.raw}` and `${__field.name}` in URLs

---

## Field Overrides

Apply specific field options to individual series/columns rather than all data:

1. Click **+ Add field override** in the Overrides section
2. Choose override target:
   - Fields with name (exact match)
   - Fields with name matching regex
   - Fields with type (number, string, time)
   - Fields returned by query (A, B, C...)
3. Add properties to override (unit, color, alias, thresholds, etc.)

Example: In a table with columns `cpu_idle` and `cpu_used`, set `cpu_used` to show as percentage and color by threshold while leaving `cpu_idle` with default styling.

---

## Transformations

Transformations reshape query data before rendering. Apply multiple in sequence.

Access: Panel editor > Transform tab > Add transformation

### Most-Used Transformations

| Transformation | Description |
|----------------|-------------|
| **Reduce** | Collapse a time series to a single value (last, mean, sum, max, min) |
| **Filter by name** | Keep only specific fields/columns |
| **Filter by value** | Filter rows where a field matches a condition |
| **Organize fields** | Rename, reorder, or hide fields |
| **Merge** | Combine multiple query results into one table |
| **Join by field** | SQL-style join on a common field (e.g., time) |
| **Group by** | Group rows and aggregate (count, sum, mean, etc.) |
| **Sort by** | Sort rows by a field |
| **Limit** | Keep only first N rows |
| **Add field from calculation** | Add a new column computed from existing columns |
| **Convert field type** | Change a field's data type |
| **Rename by regex** | Batch rename fields using regex |
| **Extract fields** | Parse JSON or regex from a string field |
| **Labels to fields** | Convert label key/values into separate columns |
| **Rows to fields** | Pivot: turn row values into column headers |
| **Prepare time series** | Normalize time series format |
| **Time series to table** | Convert time series format to table format |

Enable "Debug" toggle on any transformation to see input/output for troubleshooting.

---

## Query Options

### Multiple queries
Add multiple queries (A, B, C...) to one panel. They are overlaid in the visualization. Use this to compare metrics or show multiple services on one graph.

### Expressions (server-side)
Server-side expressions allow math across query results:
- **Math**: `$A + $B`, `$A / $B * 100`
- **Reduce**: Collapse a series to scalar
- **Resample**: Change time resolution of a series
- **Classic conditions**: Threshold logic (used in alerting)

Example - calculate error rate as percentage:
```
Query A: total_requests{job="api"}
Query B: error_requests{job="api"}
Expression C (Math): $B / $A * 100
Display C as percentage
```

### Important query variables
These variables are available in queries:

| Variable | Description |
|----------|-------------|
| `$__interval` | Auto-calculated interval based on time range and resolution |
| `$__rate_interval` | Interval suitable for rate() functions (at least 4x scrape interval) |
| `$__from` | Start of the current time range (ms epoch) |
| `$__to` | End of the current time range (ms epoch) |
| `$__range` | Duration of current time range (e.g., "6h") |
| `$__range_s` | Duration in seconds |
| `$__range_ms` | Duration in milliseconds |

Example PromQL using interval variable:
```promql
rate(http_requests_total[${__rate_interval}])
```

---

## Panel Inspect

Click panel menu (3-dot) > **Inspect** to access:
- **Data**: Raw table view of the data powering the panel
- **Stats**: Query performance (time, row count)
- **JSON**: Panel JSON model
- **Query**: Equivalent of query inspector showing raw query and response

---

## Performance Tips

1. Limit max data points to avoid over-fetching
2. Use recording rules in Prometheus for expensive queries
3. Set longer min intervals for historical dashboards
4. Use `$__interval` variable in queries to align with time resolution
5. Use `$__rate_interval` instead of hardcoded intervals for rate() queries
6. Avoid too many panels on one dashboard (aim for <20)
