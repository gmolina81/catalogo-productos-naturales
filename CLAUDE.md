# CLAUDE.md — Estándares de Codificación del Proyecto

Este archivo define los estándares de desarrollo para **M&M Vida Saludable** —
una aplicación web full-stack compuesta por base de datos (Supabase/Postgres),
backend (API REST de Supabase + funciones serverless en Vercel) y frontend
(HTML/CSS/JS, eventualmente TypeScript/React).

La fuente de verdad funcional es `SPEC.md`. Este archivo define **cómo** se
escribe el código; `SPEC.md` define **qué** hace el código.

---

## 1. Principios rectores

1. **SDD (Spec-Driven Development).** El código es consecuencia del `SPEC.md`,
   nunca al revés. Si un cambio en el código no se refleja primero en la spec,
   la spec queda desincronizada y deja de ser fuente de verdad.
2. **TDD (Test-Driven Development).** Los tests se escriben antes del código y
   deben fallar antes de implementarse. Los tests son el contrato ejecutable
   del SPEC.
3. **Seguridad por defecto.** Las decisiones sensibles (RLS, secretos, auth)
   no se resuelven al final. Se diseñan desde el primer commit.
4. **Trazabilidad.** Cada commit, cada PR y cada migración deben poder
   vincularse a una sección del SPEC o a un issue.
5. **Mínima ceremonia, máxima disciplina.** Las reglas existen para reducir
   fricción, no para sumarla. Si una regla no agrega valor, se debate y se
   cambia en este archivo antes de ignorarla.

---

## 2. Estructura del repositorio

```
mm-vida-saludable/
├── CLAUDE.md                 # Este archivo (estándares)
├── SPEC.md                   # Especificación funcional y técnica
├── README.md                 # Intro, setup, comandos
├── CHANGELOG.md              # Autogenerado desde commits
├── .env.example              # Plantilla de variables (sin valores reales)
├── .gitignore
├── .nvmrc                    # Versión de Node fijada
├── package.json
├── package-lock.json
├── vercel.json               # Config de hosting y headers de seguridad
│
├── public/                   # Assets estáticos servidos tal cual
│   └── index.html            # Catálogo público (entry point)
│
├── src/                      # Código de la app
│   ├── lib/                  # Lógica pura, reutilizable, sin DOM
│   │   ├── supabase-client.js
│   │   ├── cart.js
│   │   ├── pricing.js        # Cálculos pack↔bulto, markups
│   │   └── sync.js           # Lógica de detección de cambios del proveedor
│   ├── pages/                # Vistas (una por ruta)
│   │   ├── catalog.js
│   │   ├── checkout.js
│   │   └── admin/
│   └── components/           # Piezas reutilizables de UI
│
├── api/                      # Vercel Serverless Functions
│   ├── sync-provider.js      # Pull de la Sheet, diff contra snapshot
│   └── ...
│
├── supabase/
│   ├── migrations/           # SQL numerado (timestamp_nombre.sql)
│   ├── seed.sql              # Datos semilla para dev
│   ├── policies/             # RLS por tabla (un .sql por tabla)
│   └── tests/                # pgTAP para RLS y triggers
│
├── tests/
│   ├── unit/                 # Vitest — lógica pura
│   ├── integration/          # Vitest — llamadas al cliente Supabase (con DB local)
│   └── e2e/                  # Playwright — flujos del usuario
│
└── docs/                     # Decisiones de diseño, ADRs, diagramas
    └── adr/                  # Architecture Decision Records
```

> Si el proyecto migra a un framework (Vite + React, Next.js, etc.), esta
> estructura se ajusta en una ADR y se actualiza acá. No se improvisa.

---

## 3. Stack y versiones

| Capa             | Tecnología                         | Notas                                                                               |
| ---------------- | ---------------------------------- | ----------------------------------------------------------------------------------- |
| Frontend         | HTML5 + CSS + JavaScript (ES2022+) | Posible migración a TypeScript/React documentada en ADR cuando el admin lo amerite. |
| Base de datos    | PostgreSQL (Supabase)              | Migraciones versionadas con Supabase CLI.                                           |
| Auth             | Supabase Auth                      | Email + contraseña en v1. MFA a definir (ver SPEC §9).                              |
| Serverless       | Vercel Functions (Node.js LTS)     | Solo para operaciones que requieren `service_role` key.                             |
| Tests unit/integ | Vitest                             | Mismo runner para lógica pura y llamadas al cliente.                                |
| Tests E2E        | Playwright                         | Flujos críticos: checkout, login admin, gestión de pedidos.                         |
| Tests DB         | pgTAP                              | RLS y triggers se testean en la base, no desde JS.                                  |
| Lint/Format      | ESLint + Prettier                  | Config en `eslint.config.js` y `.prettierrc`.                                       |
| Commits          | Conventional Commits               | Validados con commitlint en pre-commit.                                             |
| CI               | GitHub Actions                     | Pipeline obligatorio antes de merge.                                                |

Versiones de Node y npm se fijan en `.nvmrc` y `package.json` (`"engines"`).
Dependencias con versiones fijas en `package.json`; el `package-lock.json`
se commitea siempre.

---

## 4. Logging

Frontend y serverless funcionan distinto; cada uno tiene su regla.

### 4.1 Serverless Functions (Node.js)

Logging estructurado en JSON. Vercel captura `stdout` y lo indexa.

```js
import { logger } from '../src/lib/logger.js'

logger.info('sync_started', { provider_id })
try {
  // ...
  logger.info('sync_completed', { provider_id, changes })
} catch (err) {
  logger.error('sync_failed', { provider_id, error: err.message, stack: err.stack })
  throw err
}
```

Reglas:

- `logger.info` para inicio/fin de operación y métricas (conteos, duraciones).
- `logger.warn` para anomalías recuperables.
- `logger.error` con `stack` completo para errores.
- **Nunca** usar `console.log` en código que va a producción.
- Nunca loguear secrets, JWTs, passwords, ni datos personales completos
  (PII). Si es necesario loguear un email, hacer hash o enmascarar.

### 4.2 Frontend

- `console.debug`/`info`/`warn`/`error` está OK durante desarrollo.
- Errores no manejados y promesas rechazadas se capturan con
  `window.addEventListener('error', ...)` y `'unhandledrejection'` y se
  envían a un servicio de observabilidad (Sentry free tier planeado).
- **Nunca** loguear tokens de Supabase ni contenido de pedidos ajenos.

---

## 5. Manejo de errores

- Toda operación de I/O (fetch, llamada a Supabase, lectura de Sheet) va
  dentro de `try/catch`.
- No capturar `Error` sin loguear con contexto suficiente para investigar.
- Validar precondiciones al inicio de cada función y lanzar errores
  descriptivos:

```js
function propagarNuevoCosto(idProductoProveedor, nuevoPrecio) {
  if (!idProductoProveedor) {
    throw new Error('idProductoProveedor es requerido')
  }
  if (typeof nuevoPrecio !== 'number' || nuevoPrecio < 0) {
    throw new Error(`nuevoPrecio inválido: ${nuevoPrecio}`)
  }
  // ...
}
```

- En el frontend, los errores visibles al usuario deben ser **en español**,
  claros, sin jerga técnica. Los detalles técnicos van al log.
- Errores de Supabase que sean consecuencia de RLS (`42501`, "new row
  violates row-level security policy") se tratan como bug, no como input
  del usuario: significa que el frontend intentó una operación no
  autorizada y hay que arreglarlo.

---

## 6. Tests

### 6.1 Pirámide de testing

- **70% unit:** lógica pura en `src/lib/`. Sin DOM, sin red, sin DB.
  Corren en milisegundos.
- **20% integration:** llamadas al cliente Supabase contra una DB local
  levantada con `supabase start`. Testean que las queries funcionan y que
  las RLS permiten/bloquean lo correcto desde JS.
- **10% E2E:** flujos críticos end-to-end con Playwright contra un entorno
  de staging o la DB local.

### 6.2 Reglas generales

- Los tests se escriben **antes** del código (TDD). Un PR sin tests de la
  funcionalidad que agrega no se mergea.
- Cobertura no es la métrica principal, pero no puede bajar entre PRs.
- Tests deterministas: sin dependencia de hora, red externa, orden de
  ejecución. Si necesitás timestamps, usá fakes (`vi.useFakeTimers()`).
- Cada test describe **una** conducta. Si un test necesita más de 3
  assertions independientes, probablemente son varios tests.

### 6.3 Tests de RLS (pgTAP)

Las políticas de seguridad son código y se testean como código. Cada
política de RLS tiene al menos tres tests en `supabase/tests/`:

1. Usuario `anon` no puede hacer lo que no debe.
2. Usuario `authenticated` (admin) sí puede hacer lo que corresponde.
3. Casos borde relevantes (ej. `productos_negocio.activo = false` no se lee
   públicamente).

```sql
-- supabase/tests/products_rls.sql
BEGIN;
SELECT plan(3);

-- Setup
SELECT tests.create_supabase_user('admin_test');

-- Test 1: anon NO puede leer productos inactivos
SELECT tests.clear_authentication();
SELECT is_empty(
  $$ SELECT * FROM productos_negocio WHERE activo = false $$,
  'anon no puede leer productos inactivos'
);

-- Test 2: anon SÍ puede leer productos activos
SELECT results_eq(
  $$ SELECT count(*)::int FROM productos_negocio WHERE activo = true $$,
  ARRAY[3],
  'anon lee productos activos'
);

-- Test 3: anon NO puede insertar en productos_negocio
SELECT throws_ok(
  $$ INSERT INTO productos_negocio (nombre_publico) VALUES ('hack') $$,
  'new row violates row-level security policy for table "productos_negocio"'
);

SELECT * FROM finish();
ROLLBACK;
```

> No aceptar un PR que agrega una tabla nueva sin su archivo de tests RLS.

### 6.4 Tests E2E (Playwright)

Flujos obligatorios desde la Fase 1:

- Cliente arma carrito → checkout → confirma pedido → ve número.
- Admin no autenticado intenta entrar a `/admin/catalogo` → redirect a
  login.
- Admin se loguea → ve el listado de pedidos → cambia un estado → ve el
  cambio reflejado y en `admin_audit_log`.
- Admin dispara sync del proveedor con cambios mockeados → revisa y
  aplica → precios de packs en modo markup se recalculan.

### 6.5 Ejecutar tests

```bash
npm run test:unit          # Vitest en modo run
npm run test:unit:watch    # Vitest en modo watch (dev)
npm run test:integration   # Vitest contra DB local
npm run test:rls           # pgTAP (requiere supabase start)
npm run test:e2e           # Playwright headless
npm run test:e2e:ui        # Playwright con UI (debug)
npm run test:all           # Todo en serie (comando pre-merge)
```

---

## 7. Estructura y estilo de código

### 7.1 Funciones

- **Máximo 50 líneas** por función. Si supera, dividir.
- JSDoc obligatorio para funciones exportadas. TypeScript con tipos nativos
  si/cuando se migre.
- Nada de variables de una letra fuera de índices simples (`i`, `j`).
- Nada de funciones anidadas con cierres sobre muchas variables; sacar a
  helpers con nombres.

```js
/**
 * Consolida pedidos de clientes en cantidades a pedir al proveedor.
 * @param {Pedido[]} pedidosConfirmados
 * @returns {LineaOrdenProveedor[]}
 */
export function generarOrdenProveedor(pedidosConfirmados) {
  // ...
}
```

### 7.2 Nombres

- Español para dominio de negocio (`productosNegocio`, `mapeoPackBulto`,
  `consolidarPedidos`). Es el vocabulario que usa el cliente y el SPEC.
- Inglés para conceptos técnicos genéricos (`getCurrentUser`,
  `parseJSON`). No mezclar en el mismo identificador.
- Constantes en `SCREAMING_SNAKE_CASE`. Tablas y campos de DB en
  `snake_case`. Funciones y variables JS en `camelCase`. Componentes de UI
  en `PascalCase`.

### 7.3 Formato

- Prettier con config por defecto + 2 espacios, comillas simples, sin
  punto y coma al final… **o el inverso**: se decide una vez en
  `.prettierrc` y no se discute más.
- ESLint con `eslint:recommended` + reglas específicas en el config del
  repo.
- Pre-commit hook con Husky corre Prettier + ESLint + commitlint antes de
  dejar commitear.

### 7.4 Imports

- Orden: nativos de Node > librerías externas > imports del proyecto
  (`src/...`) > imports relativos (`./`, `../`). Separados por una línea en
  blanco entre grupos.
- Evitar imports relativos largos (`../../../lib/...`). Configurar aliases
  (`@/lib/...`) cuando aparezca el tercer `../`.

---

## 8. Base de datos

### 8.1 Migraciones

- Toda modificación del esquema pasa por un archivo en
  `supabase/migrations/` con nombre `YYYYMMDDHHMMSS_descripcion.sql`.
- **Nunca** editar una migración ya commiteada; si algo salió mal, se crea
  otra migración que corrige.
- Cada migración que crea tabla debe, en el mismo archivo:
  1. Crear la tabla.
  2. `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`
  3. Definir al menos una política.
  4. Crear índices sobre columnas usadas en políticas RLS
     (`auth.uid()`, FKs referenciadas, flags de visibilidad).
- El seed (`supabase/seed.sql`) contiene datos de prueba para desarrollo.
  Nunca datos reales del negocio.

### 8.2 RLS (Row Level Security)

Reglas no negociables, basadas en las recomendaciones actuales de Supabase:

- RLS habilitado en **todas** las tablas del schema `public`. Sin
  excepciones.
- Toda política especifica explícitamente el rol con `TO`:
  `CREATE POLICY ... FOR SELECT TO authenticated USING (...)`. No usar
  `TO public` salvo que la intención literal sea "cualquiera, incluso
  anon".
- Funciones en políticas se envuelven en `SELECT` para aprovechar el
  `initPlan` del optimizador:

  ```sql
  -- ✗ Lento
  USING ( auth.uid() = user_id )
  -- ✓ Rápido
  USING ( (SELECT auth.uid()) = user_id )
  ```

- Cada columna usada en políticas debe tener índice.
- El SQL Editor del dashboard corre como `postgres` y **bypassea RLS**.
  Nunca validar políticas desde ahí. Siempre testear desde el cliente
  (pgTAP o integration test desde el SDK).
- `UPDATE` siempre lleva `USING` **y** `WITH CHECK` para que no se puedan
  insertar filas que luego no se pueden leer.

### 8.3 Secretos de la DB

- La `anon` key es pública por diseño: está en el bundle del frontend.
  Seguridad descansa en RLS, no en ocultarla.
- La `service_role` key **jamás** aparece en código que corra en el
  navegador. Solo en variables de entorno de Vercel Functions.
- Nunca commitear `.env`. Solo `.env.example` sin valores reales.

---

## 9. Autenticación y seguridad (resumen operativo)

La especificación completa está en `SPEC.md §6`. Acá solo la regla
operativa para código:

- Toda ruta nueva bajo `/admin/*` debe redirigir a `/admin/login` si no
  hay sesión válida **antes** de renderizar cualquier cosa.
- Toda función serverless nueva que haga algo sensible valida el JWT del
  header `Authorization: Bearer ...` con `supabase.auth.getUser(token)`
  antes de ejecutar. Si falla, responde 401 y termina.
- Toda operación que modifique `productos_negocio`,
  `productos_proveedor`, `ordenes_proveedor` o estados de pedidos debe
  insertar una fila en `admin_audit_log`. Si se olvida el audit, el PR no
  se mergea.
- `innerHTML` solo con contenido que vos generaste. Cualquier string que
  venga del usuario o de la DB se pinta con `textContent`.
- Inputs de formularios se validan en cliente (UX) **y** en la DB
  (integridad). Nunca confiar solo en el frontend.

Antes de marcar cualquier feature como "lista", revisar el checklist de
§6.8 del SPEC.

---

## 10. Artefactos obligatorios

Antes de escribir una línea de código, el repo debe tener:

- `SPEC.md` — ya existe. Fuente de verdad funcional.
- `CLAUDE.md` — este archivo.
- `README.md` — setup, comandos, variables de entorno requeridas
  (apuntando a `.env.example`).
- `package.json` con versiones fijas y scripts `dev`, `build`, `test:*`,
  `lint`, `format`.
- `.env.example` — listado de todas las variables necesarias, vacías.
- `.nvmrc` con la versión de Node.
- `vercel.json` con headers de seguridad (CSP, HSTS, etc.) como indica
  SPEC §6.6.
- `supabase/` inicializado con `supabase init`.

Si alguno falta al arrancar una tarea nueva, la tarea incluye crearlo.

---

## 11. Flujo de trabajo por requerimiento

Seguir este orden sin saltear pasos:

1. **Leer la sección relevante del `SPEC.md` completa.** Si algo no está
   especificado, no inventar: pedir confirmación o proponer cambio al
   SPEC.
2. **Planificar (Plan Mode) antes de tocar archivos.**
   - Identificar entidades, tablas, rutas, funciones involucradas.
   - Identificar decisiones abiertas (SPEC §9) que afecten esta tarea.
   - Listar casos borde no contemplados.
   - Confirmar plan.
3. **Actualizar `SPEC.md` si hace falta.** Si el plan revela un hueco en
   la spec, llenarlo primero.
4. **Escribir los tests** (TDD):
   - pgTAP para cambios de RLS o triggers.
   - Vitest unit para lógica pura.
   - Vitest integration para flujos con DB.
   - Playwright para flujos de usuario nuevos.
5. Correr los tests → deben **fallar**. Si pasan, el test está mal.
6. **Implementar** hasta que pasen.
7. **Correr el suite completo** (`npm run test:all`).
8. **Commitear** siguiendo Conventional Commits (§12).
9. **PR** con descripción que referencie la sección del SPEC y liste
   checklist de seguridad cuando aplique.

---

## 12. Commits y ramas

### 12.1 Conventional Commits

Formato obligatorio:

```
<tipo>(<scope opcional>): <descripción en minúscula, imperativo presente>

<cuerpo opcional>

<footer opcional>
```

Tipos permitidos: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`,
`test`, `build`, `ci`, `chore`, `revert`.

Scopes sugeridos para este proyecto: `catalogo`, `checkout`, `admin`,
`sync`, `db`, `rls`, `auth`, `spec`, `ci`.

Ejemplos:

```
feat(checkout): agregar validación de email del cliente
fix(sync): manejar celdas vacías en Sheet del proveedor
docs(spec): aclarar política de precio en modo markup
refactor(admin)!: mover estado de pedido a enum en DB

BREAKING CHANGE: la columna pedidos.estado pasa de text a enum;
requiere migración manual para entornos existentes.
```

Validados por commitlint pre-commit; PRs con commits mal formados se
rechazan.

### 12.2 Ramas

- `main` — protegida. Siempre desplegable. Merge solo por PR con CI verde.
- `feat/<scope>-<breve>`, `fix/<scope>-<breve>`, `chore/<breve>` — ramas
  cortas, una por tarea. Se mergean por squash para que el historial de
  `main` quede limpio y cada commit represente un cambio cerrado.

### 12.3 Versionado

- Versión de la aplicación: SemVer (`MAJOR.MINOR.PATCH`).
- Versión del SPEC: independiente, documentada en el Historial de cambios
  del propio SPEC.
- `CHANGELOG.md` se autogenera desde commits convencionales
  (semantic-release o equivalente) al mergear en `main`.

---

## 13. CI/CD

Pipeline mínimo en GitHub Actions para cada PR a `main`:

```
1. Checkout + setup Node (desde .nvmrc)
2. npm ci
3. npm run lint
4. npm run test:unit
5. npm run test:integration  (levanta Supabase local)
6. npm run test:rls
7. npm run test:e2e          (contra build preview)
8. Build de la app
```

PR no se puede mergear si alguno de los pasos falla. Dependabot/Renovate
activo para alertas de CVEs en dependencias.

Despliegue: push a `main` → deploy automático en Vercel.

---

## 14. Gestión de cambios en el requerimiento

Si durante el desarrollo aparece un cambio funcional:

1. **Detener la implementación.**
2. **Actualizar `SPEC.md`** primero, en un commit separado con tipo
   `docs(spec): ...`.
3. **Actualizar los tests** para reflejar el nuevo comportamiento.
4. **Recién entonces** modificar el código.

> El código es consecuencia del SPEC, nunca al revés.

---

## 15. Accesibilidad y UX

Aunque no sea una aplicación crítica, el catálogo público es la cara del
negocio y los controles administrativos los usa una persona real todos los
días. No se acepta:

- Contraste insuficiente (WCAG AA como mínimo).
- Formularios sin `<label>` asociado.
- Imágenes sin `alt` descriptivo.
- Elementos interactivos no alcanzables por teclado.
- Mensajes de error genéricos tipo "Error". Deben decir qué pasó y qué
  hacer.

Tests rápidos: Lighthouse o `axe-core` en el flujo de E2E de Playwright.

---

## 16. Documentación

- `README.md`: cómo levantar el proyecto en local en menos de 5 minutos.
- `SPEC.md`: qué hace el sistema.
- `CLAUDE.md` (este archivo): cómo se escribe el código.
- `docs/adr/NNNN-titulo.md`: decisiones arquitectónicas significativas.
  Formato: contexto, decisión, consecuencias, fecha. Una ADR por decisión
  irreversible (elección de framework, cambio de proveedor de auth, etc.).

Comentarios en código: explicar el **porqué**, no el **qué**. El código
dice qué hace; el comentario dice por qué se decidió así cuando no es
obvio.

---

## Historial de cambios

| Versión | Fecha      | Cambios                                                                                                                                                                                                                                                                 |
| ------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1.0     | 2026-04-23 | Adaptación inicial desde CLAUDE.md global de data engineering a proyecto full-stack web (Supabase + HTML/JS + Vercel). Incorpora SDD, TDD con pirámide unit/integration/E2E, testing de RLS con pgTAP, Conventional Commits, seguridad operativa, accesibilidad y ADRs. |
