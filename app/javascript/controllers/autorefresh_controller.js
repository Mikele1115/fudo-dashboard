import { Controller } from "@hotwired/stimulus"

// Recarga la página cada N segundos mientras el elemento exista (p. ej. "Sincronizando…").
export default class extends Controller {
  static values = { seconds: { type: Number, default: 5 } }

  connect() {
    this.timer = setTimeout(() => Turbo.visit(window.location.href, { action: "replace" }), this.secondsValue * 1000)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
