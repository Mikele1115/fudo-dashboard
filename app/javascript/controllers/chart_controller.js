import { Controller } from "@hotwired/stimulus"

// Dibuja un gráfico de Chart.js a partir del JSON en data-chart-config-value.
//   <canvas data-controller="chart" data-chart-config-value='{"type":"bar","labels":[...],"datasets":[...]}'>
// Chart.js se carga desde el CDN en el layout (window.Chart).
export default class extends Controller {
  static values = { config: Object }

  connect() {
    if (!window.Chart) return
    const { type, labels, datasets } = this.configValue
    // Un color por serie; en el gráfico de años el más reciente es el primero (azul fuerte) y los antiguos se apagan.
    const palette = ["#2563eb", "#9ca3af", "#f59e0b", "#10b981", "#8b5cf6", "#ec4899", "#14b8a6", "#f97316", "#64748b", "#a3e635"]
    const fmt = new Intl.NumberFormat("es", { maximumFractionDigits: 0 })

    this.chart = new Chart(this.element, {
      type,
      data: {
        labels,
        datasets: datasets.map((d, i) => ({
          ...d,
          backgroundColor: (d.type || type) === "line" ? "transparent" : palette[i % palette.length],
          borderColor: palette[i % palette.length],
          borderWidth: (d.type || type) === "line" ? 2 : 0,
          pointRadius: (d.type || type) === "line" ? 2 : 0,
          tension: 0.25,
          spanGaps: true,
          borderRadius: 3
        }))
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: "index", intersect: false },
        plugins: {
          legend: { position: "bottom", labels: { boxWidth: 12 } },
          tooltip: { callbacks: { label: (c) => ` ${c.dataset.label}: ${c.raw == null ? "—" : fmt.format(c.raw)}` } }
        },
        scales: {
          x: { grid: { display: false } },
          y: { beginAtZero: true, ticks: { callback: (v) => fmt.format(v) } }
        }
      }
    })
  }

  disconnect() {
    this.chart?.destroy()
  }
}
