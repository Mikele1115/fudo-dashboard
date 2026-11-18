// Ejecuta el controlador de verdad (app/javascript/controllers/filtro_controller.js)
// contra un DOM de mentira. No prueba el cableado de Stimulus —eso se comprueba aparte
// contra el HTML renderizado— pero sí toda la lógica: normalizar, filtrar, los textos y
// qué se enseña y qué se esconde.
import { readFileSync, writeFileSync, unlinkSync } from "node:fs";

const fuente = readFileSync(new URL("../../app/javascript/controllers/filtro_controller.js", import.meta.url), "utf8")
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}");
const tmp = new URL("./_filtro_tmp.mjs", import.meta.url);
writeFileSync(tmp, fuente);
const { default: Filtro } = await import(tmp.href);
unlinkSync(tmp);

const NOMBRES = ["mozzarella", "harina", "prosciutto", "jamon serrano", "burrata"];

function montar({ texto = "", verTodoSiVacio = false } = {}) {
  const p = (extra = {}) => ({ hidden: false, textContent: "", ...extra });
  const c = new Filtro();
  c.inputTarget = { value: texto };
  c.rowTargets = NOMBRES.map((n) => ({ hidden: false, dataset: { nombre: n } }));
  c.promptTarget = p();
  c.statusTarget = p();
  c.emptyTarget = p();
  c.tableTarget = p();
  c.queryTarget = p();
  c.hasQueryTarget = true;
  c.hasHistLinkTarget = false;
  c.totalValue = NOMBRES.length;
  c.showAllWhenEmptyValue = verTodoSiVacio;
  c.remember = () => {}; // no hay window aquí
  c.filter();
  return c;
}

const visibles = (c) => c.rowTargets.filter((r) => !r.hidden).map((r) => r.dataset.nombre);

let fallos = 0;
function comprueba(etiqueta, real, esperado) {
  const ok = JSON.stringify(real) === JSON.stringify(esperado);
  if (!ok) fallos++;
  console.log(`${ok ? "ok  " : "FALLA"} ${etiqueta}\n       real: ${JSON.stringify(real)}` +
              (ok ? "" : `\n       esperado: ${JSON.stringify(esperado)}`));
}

let c = montar();
comprueba("sin escribir nada no se enseña ninguna fila", visibles(c), []);
comprueba("  se ve la invitación y se esconde la tabla", [c.promptTarget.hidden, c.tableTarget.hidden], [false, true]);

c = montar({ texto: "moz" });
comprueba("buscando «moz» sale solo la mozzarella", visibles(c), ["mozzarella"]);
comprueba("  con el texto en singular", c.statusTarget.textContent,
          "1 de 5 insumos coincide con «moz». Haz clic en uno para ver todas sus compras y la evolución de su precio.");

c = montar({ texto: "ar" });
comprueba("una búsqueda parcial saca varias", visibles(c), ["mozzarella", "harina"]);
comprueba("  y el texto va en plural", c.statusTarget.textContent.startsWith("2 de 5 insumos coinciden"), true);

c = montar({ texto: "JAMÓN" });
comprueba("ignora mayúsculas y tildes", visibles(c), ["jamon serrano"]);

c = montar({ texto: "  jamon  " });
comprueba("ignora los espacios de los lados", visibles(c), ["jamon serrano"]);

c = montar({ texto: "trufa" });
comprueba("sin coincidencias no enseña nada", visibles(c), []);
comprueba("  y avisa, con el texto buscado", [c.emptyTarget.hidden, c.queryTarget.textContent], [false, "trufa"]);

c = montar({ texto: "", verTodoSiVacio: true });
comprueba("con «ver todos» y la caja vacía salen todas", visibles(c), NOMBRES);
comprueba("  y lo dice", c.statusTarget.textContent.startsWith("Los 5 insumos del período."), true);

c = montar({ texto: "harina", verTodoSiVacio: true });
comprueba("con «ver todos» escribir sigue filtrando", visibles(c), ["harina"]);

console.log(fallos === 0 ? "\nTODO BIEN" : `\n${fallos} FALLOS`);
process.exit(fallos === 0 ? 0 : 1);
