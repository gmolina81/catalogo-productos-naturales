# Plan de ejecución — M&M Vida Saludable

> Derivado de `SPEC.md` v1.2 y alineado a `CLAUDE.md` (SDD + TDD).
> **Fecha:** 2026-04-23 · **Estado:** Draft

---

## Fase 0 — Preparación (bloqueante, antes de cualquier código)

Objetivo: dejar el repositorio, las decisiones y la infraestructura listos para que Fase 1 pueda arrancar sin fricción.

### 0.1 Decisiones abiertas

**Cerradas (2026-04-23), documentadas en `SPEC §9.1`:**

- Modo de precio default: `markup_sobre_costo` con **20%** visible y editable por pack.
- Política de baja: **soft delete**.
- Imagen inicial del pack: URL del Excel `files/MM_productos_naturales.xlsx` (hoja `catalog`, columna `URL de Imagen`), editable por el admin.
- MFA: diferida a **v1.1**.
- Sesión admin: **1h JWT + 7d refresh**.

**Pendientes (`SPEC §9.2`, no bloquean arranque):** mínimo de compra, stock de seguridad, recordatorio de sync, fraccionamiento múltiple. Se resuelven en Fase 2/3 cuando corresponda.

### 0.2 Artefactos de repo faltantes

Según `CLAUDE.md §10`, faltan:

- `README.md` con setup local (hoy solo hay placeholder).
- `package.json` con `dev`, `build`, `test:*`, `lint`, `format`.
- `.env.example` con todas las variables (SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE, etc.) vacías.
- `.nvmrc` con versión Node LTS.
- `vercel.json` con headers de seguridad (`SPEC §6.6`).
- `supabase/` inicializado (`supabase init`).
- `.gitignore`, `eslint.config.js`, `.prettierrc`, `commitlint.config.js`, hooks Husky.
- Estructura de carpetas: `src/lib`, `src/pages`, `api/`, `supabase/migrations`, `supabase/policies`, `supabase/tests`, `tests/{unit,integration,e2e}`, `docs/adr`.

### 0.3 Tooling y CI

- GitHub Actions con pipeline de `CLAUDE.md §13`: lint → unit → integration → rls → e2e → build.
- Protección de rama `main`: no merge sin CI verde.
- Dependabot/Renovate habilitado.
- Proyecto Supabase creado (dev + prod separados) y Vercel linkeado al repo.

### 0.4 Caracterización del catálogo inicial del negocio (bloqueante Fase 1)

Antes de cargar `productos_negocio`, documentar en un script de staging reproducible los arreglos necesarios sobre la hoja `catalog` de `files/MM_productos_naturales.xlsx` (195 filas):

- **Encoding:** corregir caracteres corruptos (`Caj�` → `Cajú`, `Casta�as` → `Castañas`, `Az�car` → `Azúcar`, etc.).
- **Categorías:** consolidar variantes (`Frutas Disecadas` vs `frutas Disecadas`; `Mermelada` vs `Mermeladas`; `Mix de Frutos secos` vs `Mix Frutos secos `).
- **IDs:** 12 duplicados + 36 vacíos. Regenerar todos como UUIDs; guardar el `id` original solo como referencia auditable.
- **Precio:** 22 productos sin precio → se importan con `activo = false` para que no aparezcan al cliente hasta que el admin complete.
- **Imagen:** 6 sin imagen → placeholder hasta carga manual del admin.
- **Descripción:** 186 sin descripción → se cargan vacías; el admin las completa en Fase 2.

### 0.5 Caracterización de la Sheet del proveedor (bloqueante Fase 2)

La Sheet no es tabular. Documentar en un ADR (`docs/adr/000X-sheet-proveedor-patrones.md`) todo lo necesario para que Fase 2 no arranque a ciegas:

- **5 patrones de producto** (A–E) identificados en `SPEC §5.3.3.1`, cada uno con al menos 2 muestras reales (pegar filas del CSV) que servirán como fixtures del parser.
- **Secciones de categoría** en mayúsculas (lista completa: `FRUTOS SECOS`, `FRUTAS DISECADAS`, `SEMILLAS PREMIUM`, `LOS CAROLINOS`, `YERBAS`, `MIEL`, etc.).
- **Esquema de `codigo_externo` sintético:** `slug(nombre_base) + '|' + slug(presentacion)`. Reglas de slugificación: lowercase, sin acentos, espacios a `-`, colapsar duplicados.
- **Encoding:** la Sheet trae caracteres corruptos igual que el Excel. Pipeline de decode con `utf-8` + `ftfy` o similar si hace falta.
- **Precios vacíos vs baja:** celda vacía en una presentación existente → estado `sin_precio`, **no** baja. Desaparición total del nombre base → baja.
- **Casos borde a relevar:** filas con totales/subtotales, notas libres (`LOS PRECIOS PUEDEN VARIAR SIN PREVIO AVISO`), separadores en blanco, productos con precio alternativo embebido en texto (ej. `2kg $30000`).

**Riesgo principal:** la Sheet puede introducir patrones nuevos que rompan el parser. El parser debe loguear cualquier sección no reconocida como warning y mostrarlo en la UI de sync, nunca silenciarla.

---

## Fase 1 — Base funcional y seguridad (3 semanas)

Objetivo: catálogo público leyendo Supabase + checkout + admin mínimo con login y gestión de estados, todo con RLS probado.

### 1.1 Modelo de datos inicial (migraciones)

Orden de migraciones (una por archivo `YYYYMMDDHHMMSS_*.sql`):

1. `proveedores` + seed de fila única.
2. `admin_profiles` (extensión de `auth.users`).
3. `productos_proveedor` con columnas `nombre_base`, `nombre_original`, `presentacion`, `codigo_externo` (sintético), `precio_bulto` nullable, `estado` enum con `sin_precio`, y `reemplaza_a` (FK self-reference nullable). Índice único `(id_proveedor, codigo_externo)`. Ver `SPEC §4.1`.
4. `productos_negocio` (con `id_producto_proveedor` **nullable**, ver `SPEC §4.1`) + `mapeo_pack_bulto` (1:1 con pack).
5. `clientes` (unique por email).
6. `pedidos` + `pedido_items`.
7. `ordenes_proveedor`.
8. `sync_proveedor_logs`.
9. `admin_audit_log` con trigger/función `SECURITY DEFINER` para inserción.

Cada migración que crea tabla incluye: `ENABLE ROW LEVEL SECURITY`, al menos una policy, índices sobre columnas usadas en RLS (`CLAUDE.md §8.1`).

### 1.2 RLS — el trabajo real de seguridad

Para cada tabla, escribir primero los tests pgTAP en `supabase/tests/` y después la política en `supabase/policies/`:

- `productos_negocio`: SELECT público si `activo=true`, resto solo admin.
- `clientes`, `pedidos`, `pedido_items`: INSERT por `anon` dentro del checkout; lectura/UPDATE solo admin.
- `productos_proveedor`, `mapeo_pack_bulto`, `ordenes_proveedor`, `sync_proveedor_logs`: todo solo admin.
- `admin_audit_log`: INSERT vía trigger; admin lee; nadie UPDATE/DELETE.
- Usar `(SELECT auth.uid())` para aprovechar initPlan.

**Criterio de aceptación:** los tests de `CLAUDE.md §6.3` pasan para anon y admin en cada tabla. No se avanza sin esto verde.

### 1.3 Cuenta admin y flujo de auth

- Crear cuenta admin manualmente desde dashboard Supabase.
- Implementar `/admin/login` + guardia de ruta (`SPEC §6.3`).
- Flujo recuperación de contraseña.
- Registro de `login` (éxito y fallo) en `admin_audit_log` vía RPC.
- E2E Playwright: admin no logueado a `/admin/*` → redirect; login → acceso.

### 1.4 Migración del catálogo público

- Script de importación auditable (`scripts/seed_catalog.py` o equivalente) que:
  - Lee la hoja `catalog` de `files/MM_productos_naturales.xlsx`.
  - Aplica las normalizaciones documentadas en Fase 0.4 (encoding, categorías, IDs, precio, imagen).
  - Inserta 195 filas en `productos_negocio` con `id_producto_proveedor = NULL`, `precio_modo = markup_sobre_costo`, `markup_pct = 20`, `activo = true` (o `false` si no tiene precio).
  - Crea `mapeo_pack_bulto` placeholder (`packs_por_bulto = 1`, `merma_pct = 0`) hasta que el admin cure cada pack en Fase 2.
  - Emite log con resumen: cargados, con warnings, descartados. Nunca datos reales fuera de dev hasta validar.
- `productos_proveedor` queda vacío; se poblará en Fase 2 al conectar con la Sheet del proveedor.
- Reemplazar en `index.html` la lectura desde `gviz` por lectura desde Supabase (`productos_negocio` activos) manteniendo diseño visual actual (verde `#2E7D32`, grid responsive).

### 1.5 Carrito + checkout

- `src/lib/cart.js`: carrito en `localStorage`, agregar/editar/eliminar, contador en header.
- `/checkout`: resumen + formulario (nombre, tel, email requeridos).
- Transacción: upsert `clientes` por email → insert `pedidos` → insert `pedido_items`.
- Pantalla confirmación con número y link `wa.me` precargado.
- Tests: unit para lógica del carrito y pricing; integration contra DB local; E2E del flujo completo.

### 1.6 Panel admin mínimo: pedidos

- `/admin/pedidos`: listado con filtros, detalle, cambio de estado auditado.
- Acción "Contactar cliente" con `wa.me`.

### 1.7 Checklist pre-producción Fase 1

Ejecutar `SPEC §6.8` completo antes de cerrar fase.

**Entregables Fase 1:** app en Vercel con catálogo leyendo Supabase, checkout funcional, login admin, gestión básica de pedidos, RLS probado.

---

## Fase 2 — Curación y sincronización (3–4 semanas)

### 2.1 ABM de packs (`/admin/catalogo`)

- Vista unificada productos del proveedor ↔ packs asociados con contador.
- Filtros: "Sin packs", "Con packs", "Dados de baja", "Sin precio", por categoría.
- Formulario crear/editar pack + mapeo pack→bulto (`packs_por_bulto`, `merma_pct`).
- Toggle activo/inactivo; soft delete si no tiene pedidos.
- Cada acción → `admin_audit_log`.
- Tests: unit de `src/lib/pricing.js` (cálculo de markup), E2E del alta/edición.

### 2.2 Parser de la Sheet del proveedor (`src/lib/sync.js`)

Trabajo más denso de Fase 2. Requiere el ADR de Fase 0.5 como input.

- Lee la Sheet vía `gviz` o export CSV.
- Decodifica y normaliza encoding.
- Detector de **secciones de categoría** (filas con una sola celda en mayúsculas).
- Reconocedor de los 5 patrones (A–E) de `SPEC §5.3.3.1` — uno por módulo del parser, con un orquestador que elige el patrón según heurística.
- Genera `(nombre_base, nombre_original, presentacion, precio_bulto, categoria, codigo_externo)` por combinación.
- Cualquier fila/sección no interpretable se devuelve como warning con la fila original.
- **Tests unitarios obligatorios por patrón** con fixtures reales del CSV. Sin esto no se acepta el PR.

### 2.3 Serverless function de sync (`api/sync-provider.js`)

- Valida JWT antes de ejecutar.
- Llama al parser, compara contra snapshot según algoritmo `SPEC §5.4.1` adaptado al nuevo `codigo_externo` sintético.
- Distingue `precio vacío` (→ `sin_precio`) de `nombre_base desaparecido` (→ `baja`).
- Inserta `sync_proveedor_logs` con cambios en estado `pendiente`.
- Usa `service_role` solo dentro de la función.

### 2.4 UI `/admin/sync-proveedor`

- Botón "Sincronizar ahora".
- Listado agrupado por tipo de cambio: nuevos, precios, bajas, **sin_precio**, otros, **warnings del parser**.
- Para precios: delta, packs afectados, nuevo precio sugerido según `precio_modo`.
- **Acción "Fusionar"** entre un registro `nuevo` y uno `baja` cuando el admin considera que es el mismo producto con cambio tipográfico del proveedor → escribe `reemplaza_a` y re-apunta los packs que usaban el registro baja. Auditado como acción irreversible.
- "Aplicar todos los aceptados" en transacción; ejecuta propagación `SPEC §5.4.2`; registra en `admin_audit_log` como `aplicar_sync`.
- Historial de sincronizaciones.

### 2.5 Primera carga del snapshot del proveedor

- Ejecutar el parser contra la Sheet actual.
- Popular `productos_proveedor` con todas las combinaciones producto+presentación.
- El admin asocia manualmente cada `productos_negocio` con el `productos_proveedor` correspondiente (UI de asociación en `/admin/catalogo`) seteando `id_producto_proveedor`. 195 packs a asociar; puede hacerse en batch o incremental.

### 2.6 Tests

- Unit por cada patrón del parser con fixtures reales.
- Unit de detección de cambios (nuevo, precio, baja, sin_precio, otros).
- Unit de propagación de precio con diferentes `precio_modo`.
- Unit de fusión: `reemplaza_a` + re-apuntado de packs.
- E2E: sync con cambios inyectados → admin revisa → fusiona + aplica → precios recalculados + packs re-apuntados.

**Criterio de aceptación:** los cambios del proveedor nunca se aplican automáticamente (`SPEC §5.3.3` — política por defecto). Cualquier sección no interpretada queda visible como warning, nunca silenciada.

---

## Fase 3 — Orden al proveedor (1 semana)

### 3.1 Consolidación `/admin/orden-compra`

- Pantalla "Pedidos pendientes": `pedido_items` de pedidos `confirmado`/`preparando` no asignados.
- Algoritmo de consolidación `SPEC §5.4.3` (considerar merma).
- Vista previa con `[producto_proveedor, bultos, precio_bulto, total_linea]`.
- Botón "Generar orden": crea `ordenes_proveedor` (auditado).

### 3.2 Estados de orden

- `borrador → enviada → recibida | cancelada` con auditoría.
- Exportación PDF + link `wa.me` al proveedor.

### 3.3 Tests

- Unit del algoritmo con casos: exacto, redondeo hacia arriba, merma, múltiples pedidos.
- E2E del flujo completo.

---

## Fase 4 — Backlog post-v1

Según `SPEC §8`. No planificar hasta cerrar v1.

---

## Riesgos y cómo mitigarlos

| Riesgo                                                 | Impacto                                                          | Mitigación                                                                                                  |
| ------------------------------------------------------ | ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Sheet del proveedor sin clave estable                  | Cambios tipográficos generan falsos "nuevos" + "bajas" mes a mes | `codigo_externo` sintético + acción manual de **fusión** en UI de sync. ADR de Fase 0.5 documenta patrones. |
| Patrón nuevo en la Sheet no contemplado por el parser  | Sync silencioso e incorrecto                                     | Parser emite warning visible en UI cuando no reconoce una sección; nunca silenciar                          |
| Cambios del proveedor frecuentes durante desarrollo    | Inconsistencia de fixtures del parser                            | Trabajar contra copia congelada de la Sheet en `files/` hasta cerrar Fase 2                                 |
| RLS mal configurado filtra datos                       | Crítico (seguridad)                                              | pgTAP obligatorio en cada migración; no merge sin tests                                                     |
| Migración de `index.html` rompe UX actual              | Clientes reales ven errores                                      | Deploy preview primero; feature flag o subdominio hasta validar                                             |
| Decisión "vanilla vs React" tarde                      | Retrabajo                                                        | Decidir en ADR antes de Fase 1.5; SPEC admite ambos                                                         |
| 195 packs del Excel sin asociar al proveedor en Fase 2 | Sync no impacta a esos packs hasta asociarlos                    | UI de asociación en `/admin/catalogo` con búsqueda; asociación incremental aceptable                        |

---

## Orden de ataque recomendado (primeras tareas concretas)

1. Bootstrap del repo (Fase 0.2 y 0.3). Las 5 decisiones que bloqueaban diseño ya están cerradas en `SPEC §9.1`.
2. Caracterización del Excel del negocio (Fase 0.4) → script de normalización reproducible.
3. ADR de la Sheet del proveedor (Fase 0.5) con los 5 patrones y fixtures. No bloquea Fase 1, pero desbloquea Fase 2 y se escribe en paralelo mientras se avanza con DB + checkout.
4. Primera migración: `proveedores` + seed + RLS + tests pgTAP. Este primer ciclo valida que toda la cadena SDD+TDD+RLS funciona antes de escalar.

---

## Historial de cambios

| Versión | Fecha      | Cambios                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1.0     | 2026-04-23 | Versión inicial del plan de ejecución, derivado del SPEC v1.2.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| 1.1     | 2026-04-23 | Se alinea con SPEC v1.3. Fase 0.1 cierra las 5 decisiones que bloqueaban diseño (markup 20%, soft delete, imagen del Excel, MFA→v1.1, sesión 1h+7d). Fase 0.4 reorienta la caracterización al Excel del negocio (hoja `catalog`, 195 filas) y difiere la caracterización de la Sheet del proveedor a Fase 2. Fase 1.1 marca FK `id_producto_proveedor` como nullable. Fase 1.4 reemplaza la carga desde la Sheet del proveedor por importación desde `files/MM_productos_naturales.xlsx`.                                                               |
| 1.2     | 2026-04-23 | Se alinea con SPEC v1.4 (Opción Y: parser tolerante + fusión manual). Nueva Fase 0.5 dedicada a documentar en ADR los 5 patrones de la Sheet del proveedor (bloqueante Fase 2, no Fase 1). Fase 1.1 incorpora las columnas nuevas de `productos_proveedor` (`nombre_base`, `presentacion`, `codigo_externo` sintético, estado `sin_precio`, `reemplaza_a`). Fase 2 reescrita con parser por patrón, UI de fusión, primera carga del snapshot y asociación manual; estimación pasa de 2 a 3–4 semanas. Matriz de riesgos y orden de ataque actualizados. |
