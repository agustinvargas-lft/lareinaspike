# lareinaspike

Spike técnico para una app donde el usuario hace su pedido por Telegram y un agente compra en el supermercado desde un sandbox. Para la demo, el súper es [La Reina Online](https://www.lareinaonline.com.ar).

**Resultado: es viable.** Un agente, desde un Vercel Sandbox, hizo login, eligió una sucursal de retiro, buscó productos, armó el carrito y recorrió los 3 pasos del checkout hasta la pantalla con el botón "Finalizar compra". El envío final no se ejecutó en la prueba.

> El sandbox aísla tu infraestructura del código que corre adentro, pero tiene salida a internet: **no evita la compra**. Lo que pase con el pedido depende del código del agente.

---

## Stack

### Lo que usamos en el spike

| Pieza | Herramienta | Para qué |
|---|---|---|
| Entorno aislado | [Vercel Sandbox](https://vercel.com/docs/sandbox) | microVM Firecracker efímera (imagen `vercel/sandbox/universal`, Ubuntu 26.04), 2 vCPU / 4 GB, región `gru1` (São Paulo) |
| Navegador | [agent-browser](https://agent-browser.dev/) (Vercel Labs) + Chrome for Testing | CLI pensada para agentes: `snapshot -i` devuelve el árbol de accesibilidad con refs (`@e1`) en lugar de píxeles |
| Orquestación | Claude Code + MCP de Vercel + CLI `vercel sandbox` | Crear sandboxes, correr comandos, subir scripts y bajar capturas |
| Scripts | bash + JavaScript inyectado en la página | Pasos reutilizables (ver [Contenido](#contenido)) |

Empezamos con Playwright y migramos a agent-browser: hacía falta menos código, la instalación en Linux sale en un comando (`install --with-deps`) y la salida está pensada para que la lea un LLM.

### Lo que sugerimos para la app

| Capa | Sugerencia | Nota |
|---|---|---|
| Telegram | Chat SDK de Vercel (tiene adapter de Telegram) o un bot propio con webhook | Recibe pedidos y respuestas del usuario |
| Agente | [AI SDK](https://ai-sdk.dev) con Claude, o eve (framework de agentes durables de Vercel) | eve tiene una extensión de agent-browser con ~20 tools listas (`@agent-browser/eve`) |
| Esperas largas | Vercel Workflow (u otro motor durable) | El agente puede tener que esperar minutos u horas una respuesta del usuario |
| Navegador | `@vercel/sandbox` + `@agent-browser/sandbox` | Ver la sección siguiente |

El flujo de la app (qué se pregunta, cuándo y cómo se confirma) queda a criterio de quien la desarrolle.

---

## Cómo se sugiere desarrollar la parte sandbox + navegador

### 1. Usar el helper oficial en lugar de scripts bash

agent-browser trae un helper para Vercel Sandbox. Según su README:

```ts
import { runAgentBrowserCommand, withAgentBrowserSandbox } from "@agent-browser/sandbox/vercel";

const result = await withAgentBrowserSandbox(async (sandbox) => {
  await runAgentBrowserCommand(sandbox, ["open", "https://www.lareinaonline.com.ar/IniciarSesion.asp"]);
  return runAgentBrowserCommand(sandbox, ["snapshot", "-i"]);
});
```

- Instalar `@agent-browser/sandbox` y `@vercel/sandbox` en la app.
- En un sandbox nuevo, el helper instala las dependencias de Chromium. `installSystemDependencies: false` solo si la imagen ya las trae.
- Los scripts de este repo son la versión manual de lo mismo: sirven como referencia de los comandos y del orden de los pasos.

### 2. Preparar la imagen una vez (snapshot)

Instalar agent-browser y Chrome tarda **~60 s por sandbox**. Conviene hacerlo una vez, sacar un snapshot y crear cada sandbox desde ahí:

```bash
vercel sandbox create --name lr-base --region gru1 --timeout 15m
vercel sandbox exec lr-base bash -c "sudo npm i -g agent-browser && agent-browser install --with-deps"
vercel sandbox snapshot lr-base            # ver `vercel sandbox snapshot --help`
vercel sandbox create --snapshot <snapshot_id> --region gru1 --timeout 30m
```

(Equivale a `setup.sh`. Los comandos de `vercel sandbox` necesitan el proyecto vinculado con `vercel link`, o `--scope` y `--project`.) En el spike no llegamos a usar snapshots: cada corrida instaló todo de cero.

### 3. Región cerca del súper

Usamos `gru1` (São Paulo), la más cercana a Rosario. El sitio respondió `200` en menos de 1 s desde esa IP de AWS, sin bloqueos ni captcha. Si se suman otros súpers, vale la pena repetir esa prueba de acceso antes que nada: es el riesgo más barato de descartar.

### 4. Darle al agente tools, no solo un navegador

Dos enfoques, que se pueden combinar:

- **Navegación libre:** el LLM recibe la salida de `snapshot -i` y decide con qué ref interactuar (`click @e3`, `fill @e4 "texto"`). Es flexible ante sitios nuevos, pero más lento y menos predecible.
- **Tools por súper:** funciones tipadas (`buscarProductos`, `agregarAlCarrito`, `horarios`…) implementadas con los endpoints del [mapa del flujo](#mapa-del-flujo-en-la-reina). Son más rápidas y deterministas, pero hay que mantener un adaptador por sitio. Muchos pasos de La Reina son GET simples con cookie de sesión, así que podrían resolverse incluso sin navegador.

### 5. Sesión y estado

- agent-browser mantiene la sesión con `--session <nombre>`, y `state save` / `state load` guardan y restauran cookies. Los archivos de estado tienen tokens en texto plano: van fuera de git.
- En La Reina el **carrito vive en la cuenta** (persiste entre sesiones) y la **sucursal vive en la sesión** del navegador (hay que volver a elegirla en cada sesión nueva).
- Un sandbox Hobby dura como máximo 45 minutos por sesión (24 h en Pro). Si el agente espera respuestas largas del usuario, conviene no mantener el sandbox abierto mientras tanto.

### 6. Credenciales y red

- Pasar usuario y contraseña del súper como variables de entorno del comando (`-e` / `env`), nunca en archivos ni en logs.
- `vercel sandbox create --allowed-domain` restringe a qué dominios puede salir el sandbox. Sirve para acotar el alcance (por ejemplo, solo el dominio del súper una vez instalada la imagen), pero el endpoint de compra queda igual de accesible.

### Problemas que encontramos (para no repetirlos)

| Problema | Solución |
|---|---|
| `create` falla sin proyecto | El sandbox se crea dentro de un proyecto de Vercel (`--project` / `projectId`) |
| `failoverRegions` devuelve 402 | Solo está disponible en Pro |
| Chrome no arranca: faltan librerías | `agent-browser install --with-deps` (la imagen es Ubuntu, usa `apt`) |
| Chrome "no existe" al correr con `sudo` | Instalar y correr el navegador como usuario normal: el caché de browsers es por usuario |
| Capturas que no aparecen | agent-browser resuelve rutas relativas desde su daemon: usar rutas **absolutas** |
| Captura en blanco | Esperar el contenido (`agent-browser wait --text '…'`) antes de capturar |
| JavaScript roto al pasar por bash → eval | Mandar el script en base64: `agent-browser eval -b <base64>` |
| Comandos largos cortados por timeout del cliente | Correrlos sin esperar (detached) y leer el log después |
| Conclusiones erróneas por un selector que no matchea | "No encontré" puede ser un fallo del scraper: validar con otra fuente |

---

## Mapa del flujo en La Reina

ASP clásico, HTML generado en el servidor. El sitio llama "Ticket" al carrito.

| Paso | Cómo funciona | Decisión del usuario |
|---|---|---|
| Login | `IniciarSesion.asp`, campos `#Alias` y `#Clave` | — |
| Método de entrega | Modal `RetiroOEnvio.asp` → Retiro por sucursal → Oroño / Funes → Aplicar | Sucursal |
| Buscar | Buscador del sitio; EAN, nombre y precio salen del `gtag` de la página | Si hay varias opciones |
| Agregar | `PCompra('<EAN>')` → `GET TheTicket_G.asp?Acc=Agregar&Prod=<EAN>` | — |
| Validar mínimo | `TicketVal.asp` (mínimo **$50.000**); si pasa, redirige a `Revision.asp?TM=Sus` | — |
| 1 · Revisá tu pedido | Criterio de sustitución: `Crit=1` reemplazar, `Crit=3` no reemplazar → `Revision.asp?TM=Pedido&Crit=…` | Sustitución |
| 2 · Entrega | Días: `PedidoDiaEnt.asp` · franjas: `PedidoHorEnt.asp?E=2&L=<suc>&D=dd/mm/aaaa` · elección: `PedidoDiaHorTuSelec.asp?Dia=…&HV=<id>` | Día y franja |
| 3 · Pago | `IrAPago()` cambia de sección en el navegador; crédito, débito, efectivo, billeteras. **Se paga al retirar** | Medio de pago |
| Finalizar | `FinalizaLaCompra()` → form `fPedido` → `POST ProcesandoPedido.asp` | Confirmación |

Capturas del recorrido en [`docs/capturas/`](docs/capturas).

### Lo que no probamos

- El envío real del pedido (respuesta de `ProcesandoPedido.asp`, número de pedido, cancelación).
- Cuánto dura la sesión del sitio si el usuario tarda en responder.
- Envío a domicilio.
- Otros supermercados.

---

## Contenido

| Archivo | Qué hace |
|---|---|
| `setup.sh` | Instala agent-browser y Chrome en el sandbox |
| `login.sh` | Login (`LR_USER` / `LR_PASS` por variables de entorno) y guarda la sesión |
| `build-cart.sh` | Elige la sucursal y agrega productos por EAN: `./build-cart.sh 'Oroño y Saavedra' 7790895000782 7790895005794x8` |
| `to-entrega.sh` | Abre el paso 2 del checkout con un criterio de sustitución |
| `guard.js` | Script inyectable que solo deja salir requests a URLs autorizadas (útil para explorar un sitio sin efectos) |

Para correrlos a mano:

```bash
vercel sandbox create --name lr --region gru1 --timeout 30m
for f in setup.sh login.sh build-cart.sh to-entrega.sh guard.js; do vercel sandbox cp "$f" "lr:/vercel/$f"; done
vercel sandbox exec lr bash /vercel/setup.sh
vercel sandbox exec lr -e LR_USER=... -e LR_PASS=... bash /vercel/login.sh
```

Costo de una corrida completa en el spike: ~8 minutos, 87 s de CPU, dentro de la cuota gratuita de Hobby.
