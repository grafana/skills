# Panel types

| Panel | Use Case |
|-------|----------|
| **Time series** | Line/bar charts over time (default for metrics) |
| **Stat** | Single value with color thresholds |
| **Gauge** | Radial gauge for current value |
| **Bar gauge** | Horizontal bars for comparisons |
| **Table** | Tabular data, sortable columns |
| **Logs** | Log stream viewer (Loki) |
| **Traces** | Trace visualization (Tempo) |
| **Heatmap** | Distribution over time |
| **Histogram** | Value distribution |
| **Pie chart** | Part-to-whole ratios |
| **Geomap** | Geographic data |
| **Canvas** | Custom SVG-based layouts |
| **Node graph** | Service/topology graphs |
| **Flame graph** | CPU/memory profiling |
| **Text** | Markdown/HTML content |
| **Alert list** | Show firing alerts |

## Picking a panel type

Default is **Time series** for almost any metric-over-time visualization. Switch from the default only when:

- The user wants **one number, not a series** → Stat / Gauge / Bar gauge
- The data is **categorical, not temporal** → Pie chart / Bar gauge / Table
- The data is **logs/traces/profiles** → Logs / Traces / Flame graph (per data type)
- The data is **2D distribution** (e.g. histogram-over-time) → Heatmap
