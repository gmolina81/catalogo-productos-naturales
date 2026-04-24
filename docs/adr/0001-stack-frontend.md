# ADR 0001 — Stack frontend: Vite + React 19 + TypeScript + Tailwind 4

- **Fecha:** 2026-04-23
- **Estado:** Aceptada
- **Decidido por:** Germán Molina

## Contexto

El sitio actual es HTML/CSS/JS vanilla servido desde GitHub Pages ([legacy/index.html](../../legacy/index.html)). El `SPEC.md §3.1` plantea seguir con vanilla o migrar a React/Vite si el admin lo amerita, y el `CLAUDE.md §3` lo acepta vía ADR.

La v1 agrega un panel administrativo con al menos cinco rutas (`/admin/login`, `/admin/catalogo`, `/admin/sync-proveedor`, `/admin/pedidos`, `/admin/orden-compra`), más estado compartido (sesión de Supabase Auth, carrito del cliente), más flujos con múltiples pasos (checkout, curación, sync con reconciliación manual). Seguir con vanilla JS implicaría inventar routing, estado y componentes reutilizables desde cero en medio del desarrollo de features.

## Decisión

Adoptamos desde el arranque de Fase 0.2:

- **Build & dev server:** Vite 6.
- **UI:** React 19 con TypeScript 5 estricto.
- **Ruteo:** React Router 7.
- **Estilos:** Tailwind CSS 4 vía `@tailwindcss/vite`. Se preserva el verde de marca `#2E7D32` como color `brand` en `src/index.css`.
- **Cliente DB:** `@supabase/supabase-js`.
- **Testing:** Vitest (unit + integration) con jsdom, Playwright (E2E), pgTAP (RLS).
- **Calidad:** ESLint 9 flat config, Prettier 3, Husky + lint-staged, commitlint con Conventional Commits.
- **Estado global:** por ahora solo React state + React Router. Si aparece necesidad real, evaluamos Zustand o TanStack Query en un ADR nuevo.

## Alternativas consideradas

| Opción                             | Descartada porque                                                                                                                                |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Seguir con HTML/JS vanilla**     | Un admin con 5+ rutas y estado compartido termina reinventando routing, componentes y data-fetching. Retrabajo garantizado.                      |
| **Next.js**                        | SSR/SSG innecesario: el catálogo público lee de Supabase (no de la Sheet), el admin es post-login. Sumar complejidad de servidor no aporta acá.  |
| **Remix / TanStack Start**         | Maduros pero con curva propia. Vite + React vanilla es más común y tiene menos sorpresas.                                                        |
| **Sin Tailwind, solo CSS modules** | Válido, pero con 5 pantallas admin más el catálogo público, Tailwind acelera. Tailwind 4 además eliminó el archivo de config para casos simples. |
| **JavaScript sin TypeScript**      | CLAUDE.md deja la puerta abierta; el SPEC trabaja con entidades tipadas (enums, FKs). TypeScript paga el costo en el primer bug que evita.       |

## Consecuencias

### Positivas

- Admin con routing, componentes reutilizables y tipos correctos desde el día uno.
- Reemplaza el `index.html` actual de una sola vez cuando llegue Fase 1.4 (el sitio actual vive intacto en la rama `main` hasta el cutover).
- Vercel soporta Vite nativamente sin configuración adicional.

### Negativas / costos

- Bundle más grande que vanilla (mitigado por code-splitting por ruta).
- Más superficie de dependencias: exige Dependabot/Renovate y revisión periódica.
- Curva de entrada para quien solo hizo HTML/JS, aunque la mayoría del código de catálogo es directo.

### Puntos abiertos

- **Cutover del sitio actual:** el `index.html` y `carrito.html` viejos siguen en `legacy/` en la rama `dev`. El cambio de GitHub Pages → Vercel (o reconfigurar Pages) se hace al final de Fase 1, en un ADR posterior.
- **Estado global:** si crece, evaluar Zustand o TanStack Query en un ADR dedicado.
