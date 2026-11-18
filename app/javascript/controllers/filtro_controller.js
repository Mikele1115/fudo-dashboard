import { Controller } from "@hotwired/stimulus"

// Filtra la tabla de insumos mientras se escribe, sin recargar la página.
//
// Las filas están todas en el HTML y se muestran u ocultan aquí. Pesa un poco más la
// página, pero es lo que ya hacía antes de que el buscador existiera, y a cambio buscar
// es instantáneo: con 150 insumos no hay motivo para ir al servidor por cada letra.
//
// El servidor sigue filtrando por ?q= y pinta el mismo estado que pintaría esto, así que
// un enlace con búsqueda funciona aunque el JS no llegue a cargar. connect() recalcula lo
// mismo nada más arrancar, así que no hay parpadeo.
export default class extends Controller {
  static targets = ["input", "row", "table", "prompt", "status", "empty", "query", "histLink"]
  static values = { total: Number, showAllWhenEmpty: Boolean }

  connect() {
    this.filter()
  }

  // Enter no tiene que recargar: lo que se buscaba ya está filtrado.
  prevent(event) {
    event.preventDefault()
  }

  filter() {
    const q = this.normalize(this.inputTarget.value)
    const verTodo = q === "" && this.showAllWhenEmptyValue
    let visibles = 0

    this.rowTargets.forEach((row) => {
      const coincide = verTodo || (q !== "" && row.dataset.nombre.includes(q))
      row.hidden = !coincide
      if (coincide) visibles++
    })

    this.show(this.promptTarget, q === "" && !verTodo)
    this.show(this.emptyTarget, q !== "" && visibles === 0)
    this.show(this.statusTarget, visibles > 0)
    this.show(this.tableTarget, visibles > 0)

    if (visibles > 0) this.statusTarget.textContent = this.statusText(q, visibles, verTodo)
    if (q !== "" && visibles === 0) this.describeEmpty()
    this.remember(q)
  }

  statusText(q, visibles, verTodo) {
    const cola = " Haz clic en uno para ver todas sus compras y la evolución de su precio."
    if (verTodo) return `Los ${this.totalValue} insumos del período.${cola}`

    const verbo = visibles === 1 ? "coincide" : "coinciden"
    return `${visibles} de ${this.totalValue} insumos ${verbo} con «${this.inputTarget.value.trim()}».${cola}`
  }

  describeEmpty() {
    const texto = this.inputTarget.value.trim()
    if (this.hasQueryTarget) this.queryTarget.textContent = texto
    if (this.hasHistLinkTarget) {
      const url = new URL(this.histLinkTarget.href, window.location.origin)
      url.searchParams.set("q", texto)
      this.histLinkTarget.href = url.pathname + url.search
    }
  }

  // Deja la búsqueda en la URL para poder guardarla o compartirla, sin recargar.
  remember(q) {
    const url = new URL(window.location.href)
    const texto = this.inputTarget.value.trim()
    if (texto === "") url.searchParams.delete("q")
    else url.searchParams.set("q", texto)
    window.history.replaceState({}, "", url.pathname + url.search)
  }

  show(el, visible) {
    if (el) el.hidden = !visible
  }

  // Sin mayúsculas ni tildes: buscar "jamon" tiene que encontrar "Jamón".
  normalize(s) {
    return s.trim().toLowerCase().normalize("NFD").replace(/\p{Mn}/gu, "")
  }
}
