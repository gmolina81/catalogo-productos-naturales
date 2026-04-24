# M&M Vida Saludable

Plataforma de catálogo, pedidos y gestión de compra al proveedor.

- **Especificación:** [SPEC.md](./SPEC.md)
- **Estándares de código:** [CLAUDE.md](./CLAUDE.md)
- **Plan de ejecución:** [PLAN.md](./PLAN.md)
- **Decisiones arquitectónicas:** [docs/adr/](./docs/adr/)

## Stack

Vite 6 · React 19 · TypeScript 5 · Tailwind 4 · Supabase · Vitest · Playwright · pgTAP.
Ver [ADR 0001](./docs/adr/0001-stack-frontend.md) para el detalle.

## Setup local (primera vez)

### Prerequisitos

- [Node 22+](https://nodejs.org/) (se usa la versión fijada en `.nvmrc`).
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) corriendo (lo necesita `supabase start`).
- [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) instalado globalmente.

### Pasos

```bash
# 1. Clonar y entrar
git clone https://github.com/gmolina81/catalogo-productos-naturales.git
cd catalogo-productos-naturales
git checkout dev

# 2. Instalar deps
npm install

# 3. Variables de entorno
cp .env.example .env.local
# Editar .env.local con las keys del proyecto Supabase (ver dashboard → Settings → API).

# 4. DB local (levanta Postgres + Auth + Studio en Docker)
supabase start

# 5. Dev server
npm run dev
# → abrir http://localhost:5173
```

El comando `supabase start` imprime las keys locales (URL, anon key, service_role). Esas son las que van en `.env.local` para trabajar contra la DB local — distintas de las del proyecto en la nube.

## Scripts

| Script                     | Qué hace                                                                |
| -------------------------- | ----------------------------------------------------------------------- |
| `npm run dev`              | Dev server en [localhost:5173](http://localhost:5173).                  |
| `npm run build`            | Chequeo de tipos + build de producción en `dist/`.                      |
| `npm run preview`          | Servir el build local.                                                  |
| `npm run lint`             | ESLint sobre todo el repo.                                              |
| `npm run format`           | Prettier en modo escritura.                                             |
| `npm run format:check`     | Prettier en modo verificación (lo corre CI).                            |
| `npm run test:unit`        | Vitest unit (`tests/unit/`).                                            |
| `npm run test:unit:watch`  | Vitest unit en modo watch.                                              |
| `npm run test:integration` | Vitest integration contra DB local (requiere `supabase start`).         |
| `npm run test:rls`         | pgTAP para RLS (requiere `supabase start`).                             |
| `npm run test:e2e`         | Playwright. Levanta `npm run dev` automáticamente si no está corriendo. |
| `npm run test:e2e:ui`      | Playwright en modo UI para debug.                                       |
| `npm run test:all`         | Todo el suite en serie (pre-merge).                                     |
| `npm run supabase:start`   | Atajo a `supabase start`.                                               |
| `npm run supabase:stop`    | Atajo a `supabase stop`.                                                |
| `npm run supabase:reset`   | Resetea la DB local y re-aplica migraciones + seed.                     |

## Estructura

```
.
├── SPEC.md                 # Qué hace el sistema
├── CLAUDE.md               # Cómo se escribe el código
├── PLAN.md                 # Fases y orden de ataque
├── src/
│   ├── lib/                # Lógica pura (supabase client, cart, pricing, sync)
│   ├── pages/              # Vistas por ruta
│   ├── components/         # Piezas reutilizables de UI
│   ├── main.tsx            # Entry point React
│   ├── App.tsx             # Root component
│   └── index.css           # Tailwind + theme
├── api/                    # Vercel serverless functions (service_role only)
├── supabase/
│   ├── config.toml
│   ├── migrations/         # Esquema versionado
│   ├── policies/           # RLS por tabla (un .sql por tabla)
│   ├── tests/              # pgTAP para RLS y triggers
│   └── seed.sql            # Fixtures de dev
├── tests/
│   ├── setup.ts
│   ├── unit/               # Vitest — lógica pura
│   ├── integration/        # Vitest — contra DB local
│   └── e2e/                # Playwright
├── docs/adr/               # Architecture Decision Records
├── legacy/                 # Sitio estático anterior (se desactiva en Fase 1.4)
└── files/                  # Datos fuente (Excel del negocio, no datos sensibles)
```

## Flujo de trabajo

Seguir [CLAUDE.md §11](./CLAUDE.md): leer SPEC → plan → tests primero → implementar → `npm run test:all`. Commits con Conventional Commits (validados por commitlint via hook).

## Ramas

- `main` — producción actual (sitio estático). No se toca hasta el cutover de Fase 1.
- `dev` — rama de desarrollo de la v1.
- `feat/<scope>-<breve>`, `fix/<scope>-<breve>` — ramas cortas desde `dev`, merge por squash.

## Variables de entorno

Lista en [.env.example](./.env.example). Nunca commitear `.env*.local`.

- `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` — cliente, seguras por diseño (RLS es la barrera real).
- `SUPABASE_SERVICE_ROLE_KEY` — **solo** en Vercel Functions o scripts locales. Bypassa RLS.
- `VITE_PROVIDER_SHEET_ID` — Google Sheet del proveedor.
- `VITE_BUSINESS_WHATSAPP` — teléfono del negocio para el link `wa.me`.
