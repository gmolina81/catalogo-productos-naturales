# Especificación Técnica y Funcional — M&M Vida Saludable

> Plataforma de catálogo, pedidos y gestión de compra al proveedor.
> **Versión:** 1.5 · **Fecha:** Abril 2026 · **Estado:** Draft

---

## Tabla de contenidos

1. [Contexto y objetivo](#1-contexto-y-objetivo)
2. [Usuarios y roles](#2-usuarios-y-roles)
3. [Arquitectura general](#3-arquitectura-general)
4. [Modelo de datos](#4-modelo-de-datos)
5. [Funcionalidades detalladas](#5-funcionalidades-detalladas)
6. [Seguridad y autenticación](#6-seguridad-y-autenticación)
7. [Requisitos no funcionales](#7-requisitos-no-funcionales)
8. [Roadmap por fases](#8-roadmap-por-fases)
9. [Decisiones abiertas](#9-decisiones-abiertas)
10. [Glosario](#10-glosario)

---

## 1. Contexto y objetivo

### 1.1 Situación actual

Hoy existe un catálogo público de productos naturales publicado como sitio estático en GitHub Pages. El sitio consume una Google Sheet del proveedor mediante la API pública `gviz` de Google Sheets y muestra el listado de productos en una grilla con filtros por categoría y búsqueda. **No hay carrito, ni pedidos, ni persistencia de datos** más allá de la Sheet del proveedor.

### 1.2 Problema a resolver

- El negocio trabaja con **un único proveedor** (ver [§1.5](#15-supuestos-y-restricciones)), pero **su catálogo propio es un subconjunto curado** de lo que ofrece el proveedor: de ~100 productos del proveedor, el negocio puede elegir vender solo ~80, y además fraccionarlos.
- El catálogo del proveedor **no es igual** a la oferta del negocio. El proveedor vende en bultos (ej. bolsa de 5 kg de nueces); el negocio revende fraccionado en packs (ej. pack de 1 kg).
- **Los precios del proveedor cambian** y hoy no hay forma sistemática de detectar esas actualizaciones ni de propagarlas a los precios de venta del negocio.
- No hay forma de que el cliente arme un pedido desde la web; el contacto es únicamente por WhatsApp.
- No queda registro de pedidos, ni histórico, ni estado del pedido.
- El cálculo de lo que hay que pedirle al proveedor se hace manual y es propenso a errores.

### 1.3 Objetivo de la v1

Desarrollar una aplicación web que permita:

1. Mostrar un **catálogo público** (oferta del negocio) que el cliente pueda recorrer, filtrar y agregar al carrito.
2. Que el cliente realice un **pedido** identificándose con datos mínimos (nombre, teléfono, email).
3. Que el pedido quede **registrado** en una base de datos junto con su estado y su historial.
4. Que el admin **gestione la curación del catálogo**: elegir qué productos del proveedor vender, en qué presentación (packs) y a qué precio.
5. Que el admin pueda **revisar actualizaciones del proveedor** (productos nuevos, precios modificados, productos dados de baja) y decidir cómo propagarlas a la oferta del negocio.
6. Que la aplicación **calcule automáticamente**, a partir de los pedidos de clientes, qué y cuánto hay que pedirle al proveedor, traduciendo packs de venta a bultos de compra.
7. Que todo el panel administrativo esté **protegido detrás de autenticación** y que las operaciones sensibles (cambios de precio, alta/baja de packs, gestión de pedidos) no sean accesibles a usuarios no autenticados bajo ninguna circunstancia.

### 1.4 Fuera de alcance (v1)

- Pagos online (Mercado Pago u otros): se confirma y coordina por fuera.
- Control de stock: no se valida stock en tiempo real en la v1.
- Login de clientes con contraseña e historial propio.
- Multiusuario administrativo (vendedores, permisos). La v1 tiene un único admin; el modelo queda preparado para extensión.
- Reportería / dashboard avanzado de ventas.
- **Multiproveedor**: la v1 asume un único proveedor (ver §1.5). El modelo se deja preparado para extenderlo pero no se implementa UI para varios.

> Estos ítems se dejan como evolución para v1.1 o v2.

### 1.5 Supuestos y restricciones

- **Proveedor único.** A la fecha de la spec, el negocio trabaja con un único proveedor. El modelo de datos incluye la entidad `proveedores` para dejar preparada la extensión a múltiples proveedores sin rehacer el esquema, pero la UI y los flujos de la v1 asumen uno solo.
- **Admin único.** En la v1 existe una única cuenta administrativa. El modelo usa Supabase Auth, que ya soporta multiusuario, por lo que sumar vendedores en v1.1 es una extensión natural sin migración.
- **La fuente de verdad del catálogo del proveedor es su Google Sheet.** La app la consume en modo lectura; el negocio no edita datos del proveedor.
- **La Sheet del proveedor no es tabular.** Es una lista de precios humana con múltiples patrones de estructura (ver §5.3.3.1), secciones de categoría intercaladas, múltiples presentaciones por producto (10KG, 5KG, 1KG, etc.) y sin código natural estable: el nombre de texto libre es la única identificación disponible y puede cambiar entre sincronizaciones. El flujo de sync por eso incluye un parser específico y una acción manual de **fusión** para absorber cambios tipográficos (§5.3.3).
- **El catálogo del negocio es un subconjunto curado** de los productos del proveedor. Un producto del proveedor puede no tener ningún pack asociado (el negocio decidió no venderlo).
- **Los precios del proveedor pueden cambiar en cualquier momento** en su Sheet; la app debe detectarlo y asistir al admin en la actualización de sus propios precios.

---

## 2. Usuarios y roles

| Rol                     | Quién                                | Autenticación                                                                      | Qué puede hacer                                                                                                                                                                                                          |
| ----------------------- | ------------------------------------ | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Visitante / Cliente** | Consumidor final que navega el sitio | Ninguna. Se identifica con nombre, teléfono y email al momento de hacer el pedido. | Ver catálogo, filtrar, buscar, agregar al carrito, realizar pedido. No accede a ninguna vista administrativa ni puede modificar productos o precios.                                                                     |
| **Administrador**       | Dueño del negocio                    | Supabase Auth con email + contraseña. En v1 existe una única cuenta admin.         | Curar el catálogo del negocio, definir mapeo pack→bulto y margen de precio, revisar cambios del proveedor y actualizar precios, ver y actualizar estado de pedidos, generar la orden de compra consolidada al proveedor. |
| **Proveedor**           | Mayorista                            | No opera en el sistema.                                                            | Mantiene su Google Sheet externa, que la app consume en modo lectura.                                                                                                                                                    |

> **Distinción crítica:** "Cliente" y "Administrador" son dos cosas distintas. El cliente NO tiene usuario de Supabase Auth; es un registro en la tabla `clientes` identificado por email. El administrador SÍ tiene usuario de Supabase Auth con contraseña. Esta separación garantiza que el proceso de "hacer un pedido como cliente" nunca puede derivar en permisos administrativos.

---

## 3. Arquitectura general

### 3.1 Stack tecnológico

| Componente                | Tecnología                                                                     | Motivo                                                                                                                                                                                                                 |
| ------------------------- | ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Frontend**              | HTML + CSS + JavaScript vanilla (base actual) o React/Vite si se decide migrar | Se puede evolucionar el `index.html` actual sin rehacer nada. Si el admin crece, conviene React.                                                                                                                       |
| **Backend / DB**          | Supabase stack autohosteado (PostgreSQL + GoTrue + PostgREST + Studio)         | El stack open-source de Supabase corre en Docker via `supabase start` para dev y CI. La API REST autogenerada, RLS, y Auth se mantienen idénticos. **No depende del cloud de Supabase.** Producción se difiere a §9.2. |
| **Fuente proveedor**      | Google Sheets (la actual)                                                      | Se mantiene. Acceso de lectura vía endpoint `gviz` ya en uso.                                                                                                                                                          |
| **Hosting de producción** | Por decidir (ver §9.2)                                                         | v1 se desarrolla y valida en local. La elección de hosting (VPS único, Vercel + DB administrada, otro Postgres autohosteado, etc.) se difiere hasta validar la app con el cliente.                                     |
| **Notificaciones**        | WhatsApp Click-to-Chat (v1) / WhatsApp Business API (futuro)                   | En la v1 alcanza con generar un link `wa.me` precargado con el resumen del pedido.                                                                                                                                     |

### 3.2 Diagrama de componentes

```
┌────────────────────┐
│ Google Sheet       │  (catálogo del proveedor, read-only)
│ - productos_prov   │
└─────────┬──────────┘
          │ fetch (gviz JSON) — periódico + on demand
          ▼
┌─────────────────────────────────────────────────────────┐
│                Frontend (host por decidir, §9.2)        │
│  Zona pública (sin auth)                                │
│  - /            Catálogo público + carrito              │
│  - /checkout    Datos del cliente + confirmación        │
│                                                         │
│  Zona protegida (JWT de Supabase Auth requerido)        │
│  - /admin/login        Pantalla de autenticación        │
│  - /admin              Panel (redirect si no auth)      │
│     ├─ /catalogo       Curación de oferta               │
│     ├─ /sync-proveedor Cambios detectados del proveedor │
│     ├─ /pedidos        Gestión de pedidos               │
│     └─ /orden-compra   Consolidación al proveedor       │
└─────────┬──────────────────────────┬────────────────────┘
          │ API REST Supabase        │ WhatsApp wa.me
          │ (con JWT en header       │
          │  para rutas protegidas)  │
          ▼                          ▼
┌────────────────────────────────┐    Cliente / Admin
│  Supabase stack (autohost)     │
│  Docker compose: dev/CI local  │
│  Producción: §9.2              │
│   ├─ GoTrue (Auth)             │  (auth.users: cuenta admin)
│   ├─ PostgREST (API REST)      │
│   └─ PostgreSQL + RLS          │
│      - proveedores             │  (v1: fila única)
│      - productos_proveedor
│      - productos_negocio
│      - mapeo_pack_bulto
│      - clientes
│      - pedidos
│      - pedido_items
│      - ordenes_proveedor
│      - sync_proveedor_logs
│      - admin_audit_log         │  (trazabilidad de acciones admin)
└────────────────────────────────┘
```

### 3.3 Flujo de sincronización con el proveedor

Hay dos ciclos distintos:

**A) Sincronización del catálogo del proveedor (lectura)**

1. Un proceso (manual desde el admin o automático vía serverless function/cron) lee la Google Sheet del proveedor.
2. Compara contra el snapshot guardado en `productos_proveedor` (Supabase) y detecta:
   - Productos **nuevos** (no existen en el snapshot).
   - Productos con **precio modificado** respecto al snapshot.
   - Productos **dados de baja** (estaban en el snapshot pero no en la Sheet actual).
   - Productos con **otros cambios** (nombre, descripción, categoría).
3. Los cambios se registran en `sync_proveedor_logs` y quedan pendientes de revisión del admin.
4. Solo cuando el admin **acepta** los cambios en `/admin/sync-proveedor`, el snapshot `productos_proveedor` se actualiza y, si corresponde, se disparan las actualizaciones de precios de los packs relacionados.

**B) Curación y venta**

1. El admin abre `/admin/catalogo` y ve los productos del proveedor disponibles (snapshot).
2. Para los que quiera vender, crea uno o varios packs (`productos_negocio`) con su mapeo pack→bulto y precio de venta (manual o calculado con markup).
3. Los clientes ven esos packs en el catálogo público y arman pedidos.
4. El admin genera la orden de compra consolidada al proveedor (ver §5.3.4).

---

## 4. Modelo de datos

### 4.1 Entidades

#### `auth.users` _(Supabase Auth — manejado por la plataforma)_

Tabla gestionada por Supabase Auth. No se modifica su esquema. En la v1 contiene una única fila: la cuenta del administrador del negocio.

#### `admin_profiles` _(Supabase — extensión opcional de auth.users)_

Solo para trazabilidad del admin (v1 puede prescindir de esta tabla si se usa `auth.users.email` directamente; se deja prevista para cuando se sumen vendedores).

| Campo        | Tipo                            | Descripción                         |
| ------------ | ------------------------------- | ----------------------------------- |
| `id`         | uuid (PK, FK a `auth.users.id`) | Mismo ID que el usuario de Auth     |
| `nombre`     | string                          | Nombre a mostrar                    |
| `rol`        | enum                            | `admin` (v1) \| `vendedor` (futuro) |
| `activo`     | boolean                         | Si la cuenta está habilitada        |
| `created_at` | timestamptz                     | Alta                                |

#### `proveedores` _(Supabase)_

En la v1 contiene una única fila, pero se define como tabla para poder escalar a multiproveedor sin migraciones futuras.

| Campo               | Tipo              | Descripción                           |
| ------------------- | ----------------- | ------------------------------------- |
| `id`                | uuid (PK)         | ID interno                            |
| `nombre`            | string            | Nombre del proveedor                  |
| `sheet_id`          | string            | ID de la Google Sheet                 |
| `sheet_range`       | string (nullable) | Rango/tab de la Sheet si aplica       |
| `contacto_whatsapp` | string            | Número para mandar la orden de compra |
| `contacto_email`    | string (nullable) | Email alternativo                     |
| `activo`            | boolean           | Si está operativo                     |
| `created_at`        | timestamptz       | Alta                                  |

#### `productos_proveedor` _(Supabase — snapshot de la Sheet)_

Se actualiza mediante el flujo de sincronización (§5.3.2) y actúa como snapshot confirmado por el admin.

Cada fila representa una **combinación producto+presentación** del proveedor (ej. "Nuez Mariposa 10KG", "Nuez Mariposa 5KG" y "Nuez Mariposa 1KG" son tres filas distintas). Un mismo `nombre_base` puede tener varias filas, una por `presentacion`.

| Campo             | Tipo                             | Descripción                                                                                                             |
| ----------------- | -------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `id`              | uuid (PK)                        | ID interno                                                                                                              |
| `id_proveedor`    | uuid (FK)                        | Proveedor dueño                                                                                                         |
| `codigo_externo`  | string                           | Clave natural sintética derivada: `slug(nombre_base) + '                                                                | ' + slug(presentacion)`. Ej. `nuez-mariposa-extra-light\|10kg`. No viene del proveedor, la generamos nosotros en el parser. |
| `nombre_base`     | string                           | Nombre del producto del proveedor sin la presentación. Ej. "Nuez Mariposa Extra Light 2026".                            |
| `nombre_original` | string                           | Nombre exacto tal como aparece en la Sheet (sin normalizar), para auditoría y debug de matching.                        |
| `presentacion`    | string                           | Presentación/tamaño del bulto. Ej. "10KG", "5KG", "1KG", "caja 5kg", "unidad", "pack x 12".                             |
| `categoria`       | string                           | Sección/categoría del proveedor (ej. "FRUTOS SECOS", "FRUTAS DISECADAS").                                               |
| `descripcion`     | text (nullable)                  | Descripción larga si existe; normalmente vacío en esta Sheet.                                                           |
| `precio_bulto`    | numeric (nullable)               | Precio de esta presentación (último confirmado). Nullable: el proveedor puede dejar vacío un tamaño que está sin stock. |
| `unidad_compra`   | string                           | Igual a `presentacion` normalizado; se conserva separado por compatibilidad con el resto del modelo.                    |
| `imagen`          | string (nullable)                | URL. En esta Sheet no viene imagen; queda nullable.                                                                     |
| `estado`          | enum                             | `activo` \| `baja` \| `sin_precio` (variante visible pero sin precio publicado)                                         |
| `ultima_sync`     | timestamptz                      | Última vez confirmado contra la Sheet                                                                                   |
| `reemplaza_a`     | uuid (FK a esta tabla, nullable) | Si el admin fusionó este "nuevo" con uno "dado de baja" (cambio tipográfico), apunta al anterior. Ver §5.3.3.           |
| **Índice único**  |                                  | `(id_proveedor, codigo_externo)`                                                                                        |

#### `productos_negocio` _(Supabase — oferta curada)_

Un producto del proveedor puede generar 0, 1 o varios packs. Si tiene 0, significa que el negocio decidió no venderlo.

| Campo                       | Tipo                | Descripción                                                                                                                                                                                          |
| --------------------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                        | uuid (PK)           | ID interno                                                                                                                                                                                           |
| `id_producto_proveedor`     | uuid (FK, nullable) | Referencia al producto del proveedor. Nullable en v1: los packs importados del catálogo inicial (ver §8 Fase 1) no tienen vínculo al proveedor hasta que el admin los asocie durante el primer sync. |
| `nombre_publico`            | string              | Nombre que ve el cliente (ej. "Pack 1kg Nueces Mariposa")                                                                                                                                            |
| `categoria`                 | string              | Categoría mostrada al cliente (puede diferir de la del proveedor)                                                                                                                                    |
| `descripcion`               | text                | Descripción pública                                                                                                                                                                                  |
| `presentacion`              | string              | Ej. "1 kg", "500 g", "250 ml"                                                                                                                                                                        |
| `precio_venta`              | numeric             | Precio de venta del pack                                                                                                                                                                             |
| `precio_modo`               | enum                | `manual` \| `markup_sobre_costo`                                                                                                                                                                     |
| `markup_pct`                | numeric (nullable)  | Solo si `precio_modo = markup_sobre_costo`                                                                                                                                                           |
| `imagen`                    | string              | URL (puede heredarse del proveedor)                                                                                                                                                                  |
| `activo`                    | boolean             | Si se muestra o no en el catálogo público                                                                                                                                                            |
| `created_at` / `updated_at` | timestamptz         | Auditoría                                                                                                                                                                                            |

#### `mapeo_pack_bulto` _(Supabase)_

| Campo                 | Tipo              | Descripción                                    |
| --------------------- | ----------------- | ---------------------------------------------- |
| `id`                  | uuid (PK)         | ID interno                                     |
| `id_producto_negocio` | uuid (FK, unique) | Pack del negocio (1:1 en v1)                   |
| `packs_por_bulto`     | numeric           | Cuántos packs se sacan de 1 bulto              |
| `merma_pct`           | numeric           | % de merma esperable al fraccionar (default 0) |
| `notas`               | text              | Observaciones del admin                        |

#### `sync_proveedor_logs` _(Supabase — auditoría de sincronización)_

| Campo                | Tipo                     | Descripción                                |
| -------------------- | ------------------------ | ------------------------------------------ |
| `id`                 | uuid (PK)                | ID interno                                 |
| `id_proveedor`       | uuid (FK)                | Proveedor                                  |
| `ejecutado_en`       | timestamptz              | Cuándo corrió                              |
| `ejecutado_por`      | uuid (FK a `auth.users`) | Qué admin lo disparó (null si fue cron)    |
| `origen`             | enum                     | `manual` \| `automatico`                   |
| `cambios_detectados` | jsonb                    | `[{tipo, codigo_externo, antes, despues}]` |
| `estado`             | enum                     | `pendiente` \| `aplicado` \| `descartado`  |
| `aplicado_en`        | timestamptz (nullable)   | Cuándo lo confirmó el admin                |
| `resumen`            | jsonb                    | Conteos: `{nuevos, precios, bajas, otros}` |

#### `admin_audit_log` _(Supabase — trazabilidad de acciones sensibles)_

Registro de toda operación administrativa relevante, para investigar incidentes o comportamientos raros.

| Campo        | Tipo                     | Descripción                                                                                                                                    |
| ------------ | ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`         | uuid (PK)                | ID interno                                                                                                                                     |
| `user_id`    | uuid (FK a `auth.users`) | Quién hizo la acción                                                                                                                           |
| `accion`     | enum                     | `login` \| `logout` \| `crear_pack` \| `editar_pack` \| `eliminar_pack` \| `aplicar_sync` \| `cambiar_estado_pedido` \| `generar_orden_compra` |
| `entidad`    | string (nullable)        | Tabla afectada (ej. `productos_negocio`)                                                                                                       |
| `entidad_id` | uuid (nullable)          | ID del registro afectado                                                                                                                       |
| `detalle`    | jsonb                    | Snapshot de antes/después u otros datos relevantes                                                                                             |
| `ip_origen`  | inet (nullable)          | IP del cliente (best-effort)                                                                                                                   |
| `user_agent` | text (nullable)          | Navegador                                                                                                                                      |
| `creado_en`  | timestamptz              | Cuándo ocurrió                                                                                                                                 |

#### `clientes` _(Supabase)_

Se crea o se upserta por email en cada pedido. **No tiene relación con `auth.users`** — los clientes no se autentican en la v1.

| Campo        | Tipo              | Descripción                     |
| ------------ | ----------------- | ------------------------------- |
| `id`         | uuid (PK)         | ID interno                      |
| `nombre`     | string            | Nombre completo                 |
| `telefono`   | string            | WhatsApp preferentemente        |
| `email`      | string (unique)   | Clave natural de identificación |
| `direccion`  | string (nullable) | Si hace falta para entrega      |
| `notas`      | text              | Observaciones internas          |
| `created_at` | timestamptz       | Primer pedido                   |

#### `pedidos` _(Supabase)_

| Campo                    | Tipo        | Descripción                                                                          |
| ------------------------ | ----------- | ------------------------------------------------------------------------------------ |
| `id`                     | uuid (PK)   | ID interno                                                                           |
| `numero`                 | serial      | Número visible al cliente                                                            |
| `id_cliente`             | uuid (FK)   | Cliente                                                                              |
| `estado`                 | enum        | `pendiente` \| `confirmado` \| `preparando` \| `listo` \| `entregado` \| `cancelado` |
| `canal`                  | enum        | `web` \| `whatsapp` \| `manual`                                                      |
| `total`                  | numeric     | Total en pesos                                                                       |
| `notas_cliente`          | text        | Comentarios del cliente                                                              |
| `notas_admin`            | text        | Comentarios internos                                                                 |
| `fecha_pedido`           | timestamptz | Cuándo se hizo                                                                       |
| `fecha_entrega_estimada` | date        | Estimada                                                                             |

#### `pedido_items` _(Supabase)_

| Campo                 | Tipo      | Descripción                             |
| --------------------- | --------- | --------------------------------------- |
| `id`                  | uuid (PK) | ID interno                              |
| `id_pedido`           | uuid (FK) | Pedido                                  |
| `id_producto_negocio` | uuid (FK) | Pack vendido                            |
| `cantidad`            | integer   | Cuántos packs                           |
| `precio_unitario`     | numeric   | Precio al momento del pedido (snapshot) |
| `subtotal`            | numeric   | `cantidad * precio_unitario`            |

#### `ordenes_proveedor` _(Supabase)_

| Campo                   | Tipo                     | Descripción                                                                         |
| ----------------------- | ------------------------ | ----------------------------------------------------------------------------------- |
| `id`                    | uuid (PK)                | ID interno                                                                          |
| `numero`                | serial                   | Número visible                                                                      |
| `id_proveedor`          | uuid (FK)                | A qué proveedor se le pide                                                          |
| `estado`                | enum                     | `borrador` \| `enviada` \| `recibida` \| `cancelada`                                |
| `generada_por`          | uuid (FK a `auth.users`) | Qué admin la creó                                                                   |
| `fecha_creacion`        | timestamptz              | Cuándo se generó                                                                    |
| `ids_pedidos_incluidos` | uuid[]                   | Qué pedidos cubre esta orden                                                        |
| `detalle`               | jsonb                    | Snapshot de `[{codigo_externo, nombre, bultos_a_pedir, precio_bulto, total_linea}]` |
| `total`                 | numeric                  | Total estimado a pagarle al proveedor                                               |

### 4.2 Diagrama relacional

```
                auth.users  ◀─── admin_profiles
                     ▲
                     │ user_id
                     │
        admin_audit_log, sync_proveedor_logs.ejecutado_por,
        ordenes_proveedor.generada_por

            proveedores
                 ▲
                 │ id_proveedor
                 │
       productos_proveedor  ◀───  sync_proveedor_logs
                 ▲
                 │ id_producto_proveedor
                 │
       productos_negocio  ◀───  mapeo_pack_bulto
                 ▲
                 │ id_producto_negocio
                 │
      pedido_items  ──▶  pedidos  ──▶  clientes
                             │
                             ▼
                       ordenes_proveedor  ──▶  proveedores
```

---

## 5. Funcionalidades detalladas

### 5.1 Catálogo público (`/`)

- Grilla de productos activos (`productos_negocio.activo = true`).
- Filtro por categoría y búsqueda por nombre/descripción (equivalente al actual).
- Botón "Agregar al carrito" en cada card.
- Carrito persistente en `localStorage` del navegador.
- Ícono de carrito en el header con contador de items.
- El carrito permite editar cantidades y eliminar ítems.
- Mantener diseño visual actual (verde `#2E7D32`, layout grid responsive, card con imagen, categoría, nombre y precio).

### 5.2 Checkout (`/checkout`)

- Resumen del pedido: items, cantidades, subtotales, total.
- Formulario de identificación: nombre, teléfono, email (todos requeridos), dirección y notas (opcionales).
- Al confirmar: `upsert` del cliente por email → `insert` del pedido en estado `pendiente` → `insert` de los `pedido_items`.
- Pantalla de confirmación con el número de pedido y botón "Avisar por WhatsApp", que abre `wa.me` con el resumen precargado al número del negocio.
- Limpieza del carrito luego de confirmar.

### 5.3 Panel de administración (`/admin`)

Todas las rutas bajo `/admin/*` son **rutas protegidas**. El detalle del mecanismo de autenticación y autorización está en [§6 — Seguridad y autenticación](#6-seguridad-y-autenticación).

#### 5.3.1 Login del admin (`/admin/login`)

- Formulario: email + contraseña.
- Validación vía `supabase.auth.signInWithPassword()`.
- En caso de éxito: guarda sesión en `localStorage` (manejado por el SDK de Supabase) y redirige a `/admin`.
- En caso de fallo: mensaje genérico ("Credenciales inválidas") sin revelar si el email existe.
- Link "Olvidé mi contraseña" que dispara flujo de recuperación por email.
- Se registra la acción `login` (éxito o fallo) en `admin_audit_log`.

#### 5.3.2 Curación del catálogo (`/admin/catalogo`)

- **Vista unificada** de los productos del proveedor (`productos_proveedor`) con, al costado, los packs del negocio que los usan.
- Cada fila del proveedor muestra: nombre, categoría, unidad de compra, precio de bulto, y un contador de packs asociados (0, 1, 2, …).
- Filtros: "Sin packs" (candidatos a curar), "Con packs", "Dados de baja", por categoría.
- Acciones por producto del proveedor:
  - **Crear pack**: abre formulario para definir un nuevo `productos_negocio` (nombre público, categoría, presentación, precio_venta o markup, imagen, activo) y su `mapeo_pack_bulto` (packs_por_bulto, merma).
  - **Editar pack**: modificar cualquier campo del pack.
  - **Activar/desactivar pack**: controla visibilidad en catálogo público sin borrar histórico.
  - **Eliminar pack**: soft delete (solo si no tiene pedidos asociados; en caso contrario, solo se puede desactivar).
- Cada acción se registra en `admin_audit_log`.
- Indicador visual de productos del proveedor con `estado = baja`: los packs relacionados se marcan automáticamente como inactivos y se muestra alerta.

#### 5.3.3 Sincronización con el proveedor (`/admin/sync-proveedor`)

- Botón **"Sincronizar ahora"** que dispara un pull de la Google Sheet y genera un `sync_proveedor_logs` con los cambios detectados.
- Encabezado con resumen: última sincronización, cantidad de cambios pendientes.
- Listado de cambios pendientes agrupado por tipo:
  - **Productos nuevos:** combinaciones (nombre+presentación) que aparecen en la Sheet pero no en el snapshot. Acción: aceptar, ignorar, o **fusionar con un "dado de baja"** (ver más abajo).
  - **Precios modificados:** el `precio_bulto` de una combinación existente cambió. Se muestra antes/después, delta absoluto y %. Para cada uno, se lista qué packs del negocio lo usan y qué impacto tendría en sus precios de venta:
    - Si `precio_modo = markup_sobre_costo`: se calcula el nuevo `precio_venta` y se ofrece "Aceptar cambio" o "Mantener precio de venta actual".
    - Si `precio_modo = manual`: se marca como "Requiere revisión" y se ofrece un campo para ingresar el nuevo `precio_venta` manualmente.
  - **Productos dados de baja:** estaban en el snapshot pero ya no aparecen en la Sheet. Acción: confirmar baja o ignorar.
  - **Productos sin precio:** el producto sigue en la Sheet pero la celda de precio quedó vacía. Estado pasa a `sin_precio`; no genera baja automática (el proveedor puede estar sin stock temporal).
  - **Otros cambios (nombre, descripción, categoría):** se listan para aceptar/descartar.
- **Acción "Fusionar"**: para cada par (`nuevo`, `baja`) que el admin considere que es el mismo producto con cambio tipográfico del proveedor (ej. `Casta�as de PARA` → `Castañas de Pará 2026`), marca el `nuevo` como reemplazo del `baja` escribiendo `reemplaza_a` en el registro nuevo. La consecuencia es que los packs que apuntaban al registro dado de baja se re-apuntan al nuevo, conservando historial de pedidos. Es una acción **manual e irreversible** auditada en `admin_audit_log`.
- Botón **"Aplicar todos los cambios aceptados"** ejecuta la transacción y se registra en `admin_audit_log` como `aplicar_sync`.
- Tabla de historial de sincronizaciones con resumen por fecha.

> **Política por defecto:** los cambios del proveedor **nunca** se aplican automáticamente sin revisión.

##### 5.3.3.1 Estructura de la Sheet del proveedor (referencia para el parser)

La Sheet no es tabular. El parser debe identificar **secciones de categoría** (filas con una sola celda en mayúsculas, ej. `FRUTOS SECOS`) y dentro de cada sección reconocer al menos estos 5 patrones documentados en la Sheet actual:

| Patrón                        | Estructura                                                                                                                                  | Ejemplo                                |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| **A — dos filas**             | Fila N: nombre + headers de presentación (`10KG, 5KG, 1KG`). Fila N+1: precios alineados a esas columnas.                                   | `Nuez Mariposa`, `Almendra Non Pareil` |
| **B — una fila bajo header**  | Un header de presentaciones en una fila (ej. `5KG, 1KG`); cada producto siguiente ocupa una fila con nombre + precios.                      | Bloque `MIX DE FRUTOS SECOS`           |
| **C — tabla simple**          | Header de presentaciones una vez (ej. `25KG, 5KG, 1KG`); cada producto es una fila con nombre + precios.                                    | Bloque `SEMILLAS PREMIUM`              |
| **D — variantes bajo rótulo** | Fila con rótulo (ej. `DÁTILES CON CAROZO`); filas siguientes son variantes (`EGIPTO`, `ARGELIA PREMIUM`, `MEDJOUL`) cada una con su precio. | Bloque `DÁTILES`                       |
| **E — sub-envase**            | Producto con header de presentaciones y múltiples filas de sub-envase (ej. "Envase de kg", "Envase de medio kg").                           | `MIEL NANI`                            |

Cada patrón tiene tests específicos en `src/lib/sync.js` contra muestras reales de la Sheet. Si aparece un patrón nuevo no reconocido, el parser debe marcar la sección como "no interpretada" y el admin la ve como un warning en la UI de sync — nunca silenciar.

#### 5.3.4 Gestión de pedidos (`/admin/pedidos`)

- Listado con filtros por estado, cliente, rango de fechas.
- Detalle del pedido: ítems, cliente, totales, notas.
- Cambio de estado: `pendiente → confirmado → preparando → listo → entregado`. Cancelación con motivo. Cada cambio se audita.
- Acción "Contactar cliente": abre `wa.me` con un mensaje precargado.

#### 5.3.5 Orden de compra al proveedor (`/admin/orden-compra`)

- Pantalla **"Pedidos pendientes"**: muestra `pedido_items` de pedidos en `confirmado` o `preparando` que todavía no estén asignados a una orden enviada.
- Consolidación automática por producto del proveedor.
- Vista previa de la orden: lista de `[producto proveedor, bultos a pedir, precio_bulto, total_linea]` y total.
- Botón **"Generar orden"**: crea el registro en `ordenes_proveedor` (se registra `generada_por`).
- Acciones: marcar como `enviada`, `recibida` o `cancelada`. Todas auditadas.

### 5.4 Algoritmos clave

#### 5.4.1 Detección de cambios del proveedor

```python
def detectar_cambios_proveedor(id_proveedor):
    snapshot = {p.codigo_externo: p for p in db.productos_proveedor
                if p.id_proveedor == id_proveedor and p.estado == "activo"}
    vivos = leer_sheet_proveedor(id_proveedor)  # dict codigo_externo -> datos

    cambios = []
    for code, datos in vivos.items():
        if code not in snapshot:
            cambios.append({"tipo": "nuevo", "codigo_externo": code, "despues": datos})
        else:
            prev = snapshot[code]
            if datos.precio_bulto != prev.precio_bulto:
                cambios.append({
                    "tipo": "precio",
                    "codigo_externo": code,
                    "antes": prev.precio_bulto,
                    "despues": datos.precio_bulto,
                })
            if (datos.nombre, datos.descripcion, datos.categoria) != \
               (prev.nombre, prev.descripcion, prev.categoria):
                cambios.append({
                    "tipo": "otros",
                    "codigo_externo": code,
                    "antes": {"nombre": prev.nombre, "descripcion": prev.descripcion,
                              "categoria": prev.categoria},
                    "despues": {"nombre": datos.nombre, "descripcion": datos.descripcion,
                                "categoria": datos.categoria},
                })

    for code, prev in snapshot.items():
        if code not in vivos:
            cambios.append({"tipo": "baja", "codigo_externo": code, "antes": prev})

    return cambios
```

#### 5.4.2 Propagación de cambio de precio a packs

```python
def propagar_nuevo_costo(id_producto_proveedor, nuevo_precio_bulto):
    packs = db.productos_negocio.where(id_producto_proveedor=id_producto_proveedor)
    for pack in packs:
        if pack.precio_modo == "markup_sobre_costo":
            mapeo = db.mapeo_pack_bulto.get(id_producto_negocio=pack.id)
            costo_por_pack = nuevo_precio_bulto / mapeo.packs_por_bulto
            pack.precio_venta = costo_por_pack * (1 + pack.markup_pct / 100)
            pack.save()
        # Si precio_modo == "manual", no se toca: el admin decide en la UI.
    db.productos_proveedor.update(id=id_producto_proveedor,
                                  precio_bulto=nuevo_precio_bulto,
                                  ultima_sync=now())
```

#### 5.4.3 Consolidación pack → bulto para orden de compra

```python
def generar_orden_proveedor(pedidos_confirmados):
    acumulado = {}  # id_producto_proveedor -> packs_totales

    for pedido in pedidos_confirmados:
        for item in pedido.items:
            pack = buscar_producto_negocio(item.id_producto_negocio)
            id_prov_producto = pack.id_producto_proveedor
            acumulado[id_prov_producto] = acumulado.get(id_prov_producto, 0) + item.cantidad

    orden = []
    for id_prov_producto, packs_totales in acumulado.items():
        mapeo = buscar_mapeo(id_prov_producto)
        packs_por_bulto_efectivo = (
            mapeo.packs_por_bulto * (1 - mapeo.merma_pct / 100)
        )
        bultos = math.ceil(packs_totales / packs_por_bulto_efectivo)
        producto_prov = db.productos_proveedor.get(id=id_prov_producto)
        orden.append({
            "codigo_externo": producto_prov.codigo_externo,
            "nombre": producto_prov.nombre,
            "bultos_a_pedir": bultos,
            "precio_bulto": producto_prov.precio_bulto,
            "total_linea": bultos * producto_prov.precio_bulto,
        })
    return orden
```

**Ejemplo:** bolsa de 5 kg de nueces, pack de 1 kg (`packs_por_bulto = 5`, `merma_pct = 0`). 10 packs pedidos → `ceil(10 / 5) = 2` bolsas.

---

## 6. Seguridad y autenticación

Este capítulo es **requisito bloqueante** de la v1: ninguna funcionalidad administrativa puede liberarse a producción sin los controles acá definidos.

### 6.1 Principios

1. **Defensa en profundidad.** El frontend oculta la UI admin a no autenticados (primera barrera), pero la barrera real es la **Row Level Security de PostgreSQL**: aunque alguien pegue peticiones directo a la API de Supabase, la base rechaza la operación si no hay un JWT válido de admin.
2. **Separación de contextos.** Cliente y admin son poblaciones distintas. Los clientes no tienen cuenta de Auth. Esto elimina toda posibilidad de escalamiento de privilegios desde el flujo de checkout.
3. **Mínimo privilegio.** La API del frontend usa la **anon key** pública de Supabase. Esta clave solo puede hacer lo que las políticas RLS permitan a usuarios no autenticados. La **service role key** nunca se expone en el frontend ni se commitea al repo.
4. **Auditoría.** Toda acción sensible queda registrada en `admin_audit_log` con usuario, timestamp y detalle. Sirve para investigar ante cualquier sospecha.
5. **Secretos fuera del código.** Las credenciales y keys viven en variables de entorno del hosting (Vercel), nunca en el repo.

### 6.2 Autenticación del admin

| Aspecto                    | Decisión                                                                                                                                           |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Proveedor de identidad** | Supabase Auth (email + contraseña).                                                                                                                |
| **Creación de la cuenta**  | Manual, desde el dashboard de Supabase. No hay registro público. La página de login no tiene link "crear cuenta".                                  |
| **Política de contraseña** | Mínimo 12 caracteres, al menos 1 mayúscula, 1 número y 1 símbolo. Se valida del lado del cliente y del servidor (trigger en Supabase).             |
| **Recuperación**           | Flujo de "olvidé mi contraseña" nativo de Supabase: envía link por email con token de un solo uso y expiración de 1 hora.                          |
| **Sesión**                 | JWT con expiración de 1 hora y refresh token de 7 días (defaults razonables de Supabase). Se renueva automáticamente mientras el admin usa la app. |
| **Cierre de sesión**       | Botón "Cerrar sesión" en el header del admin que llama a `supabase.auth.signOut()`. El token queda inválido inmediatamente.                        |
| **Sesión inactiva**        | Al cabo de 1 hora sin renovación, la sesión expira y se redirige a `/admin/login`.                                                                 |
| **MFA**                    | Recomendado para v1 pero opcional; requerido para v1.1. Supabase soporta TOTP (Google Authenticator) nativamente.                                  |
| **Rate limiting en login** | Supabase aplica rate limit por IP en el endpoint de auth. Reforzar con captcha (hCaptcha, incluido en Supabase) si el riesgo lo amerita.           |

### 6.3 Protección de rutas del frontend

- Todas las rutas `/admin/*` (excepto `/admin/login`) verifican al montarse si existe una sesión válida.
- Si no hay sesión: redirect inmediato a `/admin/login`, sin renderizar contenido.
- La verificación usa `supabase.auth.getSession()` (lee del `localStorage` manejado por el SDK) y, ante duda, `supabase.auth.getUser()` (valida el JWT contra el servidor).
- El header de la zona admin muestra el email del usuario logueado y el botón de cerrar sesión.

> **Importante:** la protección en el frontend es **conveniencia de UX, no seguridad**. La seguridad real la provee RLS (§6.4). Nunca se debe confiar en que el frontend "esconde" algo.

### 6.4 Políticas RLS (Row Level Security) por tabla

Toda tabla de la base tiene RLS habilitado. Las políticas se definen así:

| Tabla                 | Quién puede leer                              | Quién puede escribir                                                        |
| --------------------- | --------------------------------------------- | --------------------------------------------------------------------------- |
| `proveedores`         | Solo admin autenticado                        | Solo admin autenticado                                                      |
| `productos_proveedor` | Solo admin autenticado                        | Solo admin autenticado (vía flujo de sync)                                  |
| `productos_negocio`   | **Público** si `activo = true`; admin ve todo | Solo admin autenticado                                                      |
| `mapeo_pack_bulto`    | Solo admin autenticado                        | Solo admin autenticado                                                      |
| `sync_proveedor_logs` | Solo admin autenticado                        | Solo admin autenticado                                                      |
| `clientes`            | Solo admin autenticado                        | **Público** (INSERT/UPSERT solo por email); admin puede UPDATE/DELETE       |
| `pedidos`             | Solo admin autenticado                        | **Público** (INSERT); admin puede UPDATE                                    |
| `pedido_items`        | Solo admin autenticado                        | **Público** (INSERT asociado a un pedido recién creado); admin puede UPDATE |
| `ordenes_proveedor`   | Solo admin autenticado                        | Solo admin autenticado                                                      |
| `admin_audit_log`     | Solo admin autenticado                        | Insertado por triggers/funciones; admin no puede UPDATE/DELETE              |
| `admin_profiles`      | Solo el propio admin puede leer su fila       | Solo admin autenticado (update limitado)                                    |

**Principios de las políticas:**

- El cliente anónimo (`role = anon`) solo puede:
  - Leer `productos_negocio` donde `activo = true`.
  - Insertar en `clientes` (upsert por email), `pedidos` e `pedido_items` dentro de la misma transacción del checkout.
- El usuario autenticado (`role = authenticated`) en v1 implica admin: tiene acceso completo a lo suyo.
- Las tablas sensibles (`productos_negocio`, `productos_proveedor`, `ordenes_proveedor`) **nunca** permiten escritura a `anon`.
- `admin_audit_log` se llena mediante triggers o funciones RPC con `SECURITY DEFINER` para que los registros sean inmutables desde el cliente.

### 6.5 Protección en la capa de API / Serverless Functions

Si se usan Vercel Functions para operaciones sensibles (ej. sincronización con la Sheet usando service role, generación de PDFs de la orden de compra):

- La función valida el JWT del admin en el header `Authorization: Bearer <token>` antes de ejecutar.
- Rechaza cualquier request que no tenga JWT válido con 401.
- Usa la **service role key** solo adentro de la función, nunca la retorna al cliente.
- Registra en `admin_audit_log` qué operación se ejecutó y por quién.

### 6.6 Hardening adicional

| Medida                   | Detalle                                                                                                                                                                                |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **HTTPS obligatorio**    | Forzado por Vercel/Netlify por defecto. HTTP Strict Transport Security (HSTS) habilitado.                                                                                              |
| **Headers de seguridad** | `Content-Security-Policy`, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin` configurados en `vercel.json` o equivalente. |
| **CORS**                 | La API de Supabase solo permite el dominio de producción (y `localhost` en dev).                                                                                                       |
| **Secretos**             | Keys de Supabase (anon) en variable de entorno pública del build; service role key solo en variables de entorno de serverless functions. `.env` en `.gitignore`.                       |
| **Dependencias**         | Dependabot o Renovate en GitHub para alertas de CVEs. Revisión antes de merge.                                                                                                         |
| **Inputs del cliente**   | Validación en frontend (UX) y backend (integridad). Todo lo que viene del usuario se trata como hostil: sanitización, límites de longitud, tipos fuertes.                              |
| **XSS**                  | Si se migra a React, el escape automático ayuda. En vanilla JS, nunca usar `innerHTML` con contenido de usuario; usar `textContent`.                                                   |
| **SQL injection**        | Imposible con el SDK de Supabase (usa parámetros prepared). Si se hace SQL crudo en funciones, usar siempre parámetros.                                                                |

### 6.7 Gestión de incidentes

- **Sospecha de compromiso de la cuenta admin:** desde el dashboard de Supabase se puede revocar la sesión actual (`auth.admin.signOut(userId)`) y forzar reset de contraseña.
- **Fuga de la anon key:** la anon key es pública por diseño; RLS es lo que protege. Si igual se quiere rotar, se hace desde Supabase y se redeploya la app.
- **Fuga de la service role key:** rotar inmediatamente desde Supabase, redeploy de las functions con la nueva key. Revisar `admin_audit_log` buscando actividad sospechosa.
- **Log retention:** `admin_audit_log` se conserva 12 meses como mínimo; exportaciones mensuales opcionales a storage.

### 6.8 Checklist de seguridad pre-producción

Antes de liberar la v1 a producción, confirmar:

- [ ] RLS habilitado en todas las tablas (`ALTER TABLE … ENABLE ROW LEVEL SECURITY`).
- [ ] Políticas probadas con usuario `anon`: no puede leer `productos_proveedor`, no puede escribir `productos_negocio`, etc.
- [ ] Anon key en variables de entorno, no hardcodeada.
- [ ] Service role key NO está en el código ni en el frontend.
- [ ] HTTPS forzado en Vercel.
- [ ] Headers de seguridad configurados.
- [ ] Contraseña del admin cumple la política y NO es la default/ejemplo.
- [ ] Flujo de recuperación de contraseña probado.
- [ ] `admin_audit_log` se llena efectivamente en login, cambios de pack, sync, etc.
- [ ] CORS restringido al dominio de producción.
- [ ] `.env` y similares en `.gitignore`; historial de git auditado para no tener secretos filtrados.

---

## 7. Requisitos no funcionales

| Aspecto                             | Requisito                                                                                                                       |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| **Rendimiento**                     | Carga inicial del catálogo < 2s en 4G. El catálogo público lee de `productos_negocio` (Supabase), no de la Sheet en vivo.       |
| **Frescura de datos del proveedor** | Sincronización manual en v1 (admin dispara el pull). Opcional v1.1: cron diario.                                                |
| **Responsive**                      | Mobile-first. La mayoría de clientes compra desde el celular.                                                                   |
| **Integridad de precios**           | Ningún cambio del proveedor impacta el precio al cliente sin revisión explícita del admin.                                      |
| **Backups**                         | Backups automáticos diarios de Supabase. Exportación manual de pedidos a CSV.                                                   |
| **Observabilidad**                  | Logs de errores del frontend en consola + opcional Sentry. `sync_proveedor_logs` y `admin_audit_log` como bitácoras auditables. |
| **Compatibilidad**                  | Chrome, Safari, Firefox, Edge últimas 2 versiones.                                                                              |
| **Accesibilidad**                   | Contrastes AA, labels correctos en formularios, navegable por teclado.                                                          |

---

## 8. Roadmap por fases

### Fase 1 — Base funcional y seguridad _(estimado: 3 semanas)_

- [ ] Setup Supabase: proyecto, tablas, RLS, seed inicial, fila única en `proveedores`.
- [ ] **Creación de la cuenta admin y validación del flujo completo de login/logout/recuperación.**
- [ ] **Políticas RLS por tabla, con pruebas desde cliente `anon` verificando que no puede acceder a lo privado.**
- [ ] Importación inicial: staging + normalización + carga de los 195 productos del archivo `files/MM_productos_naturales.xlsx` (hoja `catalog`) en `productos_negocio`. Incluye corrección de encoding, consolidación de categorías duplicadas, regeneración de IDs (hay 12 duplicados y 36 vacíos), marcado `activo = false` para los 22 productos sin precio. `productos_proveedor` arranca vacío; se poblará cuando el admin conecte packs con productos del proveedor vía sync (Fase 2).
- [ ] Migración del `index.html` a una versión que lee `productos_negocio` desde Supabase.
- [ ] Carrito + checkout + persistencia de pedidos.
- [ ] Panel admin básico protegido: login, listado de pedidos, cambio de estado.
- [ ] `admin_audit_log` operativo.
- [ ] Checklist de seguridad pre-producción (§6.8) ejecutado.

### Fase 2 — Curación de catálogo y sincronización _(estimado: 3–4 semanas)_

- [ ] ABM de `productos_negocio` con mapeo pack→bulto.
- [ ] Pantalla `/admin/catalogo` con vista unificada productos del proveedor ↔ packs.
- [ ] Parser de la Sheet del proveedor: interpreta los 5 patrones (§5.3.3.1) con tests de unidad contra muestras reales; genera `(nombre_base, presentacion, precio)` y `codigo_externo` sintético.
- [ ] Pantalla `/admin/sync-proveedor` con detección y revisión de cambios, incluyendo acción manual de **fusión** `(nuevo, baja)` para absorber cambios tipográficos del proveedor (§5.3.3).
- [ ] Estado `sin_precio` + UI que lo distingue de baja.
- [ ] Propagación de cambios de precio según `precio_modo`.
- [ ] Primera carga de `productos_proveedor` desde la Sheet actual (parser pasa por todas las combinaciones producto+presentación) y asociación manual con los `productos_negocio` importados en Fase 1.

### Fase 3 — Orden al proveedor _(estimado: 1 semana)_

- [ ] Pantalla de consolidación.
- [ ] Generación y exportación (PDF y WhatsApp) de la orden.
- [ ] Estados de la orden y trazabilidad.

### Fase 4 — Mejoras _(backlog, post-v1)_

- [ ] MFA obligatorio para el admin.
- [ ] Sincronización automática con cron (serverless function).
- [ ] Reglas automáticas de aceptación de cambios de precio (ej. < 5%).
- [ ] Multiusuario admin (roles vendedor/admin).
- [ ] Pagos online con Mercado Pago.
- [ ] Control de stock.
- [ ] Login de clientes con historial.
- [ ] Dashboard de ventas y top productos.
- [ ] Notificaciones automáticas al cliente (WhatsApp Business API).
- [ ] Soporte multiproveedor en la UI.

---

## 9. Decisiones

### 9.1 Cerradas

1. **Modo de precio por defecto** _(cerrada 2026-04-23):_ los packs nuevos arrancan en `markup_sobre_costo` con markup por defecto **20%**. El margen se muestra visible en la UI de alta/edición y es editable por pack.
2. **Borrado vs inactivación de packs** _(cerrada 2026-04-23):_ política es **soft delete**. Un pack con pedidos históricos nunca se borra físicamente; se desactiva.
3. **Imagen del pack** _(cerrada 2026-04-23):_ se usa la URL de imagen del Excel `files/MM_productos_naturales.xlsx` (hoja `catalog`, columna `URL de Imagen`) como valor inicial. El admin puede reemplazarla con otra URL. Los productos sin imagen en el Excel quedan con placeholder hasta que el admin cargue una.
4. **MFA** _(cerrada 2026-04-23):_ se difiere a **v1.1**. La v1 usa solo email + contraseña.
5. **Duración de sesión admin** _(cerrada 2026-04-23):_ **1h JWT + 7d refresh** (defaults de Supabase).

### 9.2 Abiertas

1. **Validaciones de pedido:** ¿hay mínimo de compra o zona de entrega?
2. **Stock de seguridad:** ¿margen extra en la orden al proveedor (ej. +10%)?
3. **Frecuencia de sincronización:** v1 manual. ¿Recordatorio si pasaron X días?
4. **Fraccionamiento múltiple:** ¿un pack puede combinar varios productos del proveedor?
5. **Hosting de producción.** v1 se desarrolla y valida en local con `supabase start` (Docker). Antes de v1.0 hay que decidir dónde corre la app y la DB en producción. Opciones contempladas:
   - **(a) VPS único** (Hetzner / DigitalOcean / Linode, ~$5-6/mes) corriendo el `docker-compose` autohosteado de Supabase + nginx para el frontend buildeado.
   - **(b) Frontend en hosting estático** (Vercel / Netlify / Cloudflare Pages) + Postgres + GoTrue + PostgREST en un VPS o cloud aparte. Más piezas pero separación clara entre frontend público y backend.
   - **(c) Reactivar Supabase Cloud** si los límites del free tier son aceptables. Decartado por el usuario por preferencia de no depender del SaaS, pero queda como opción de emergencia.
     La decisión se bloquea hasta validar la app con el cliente; mientras tanto el SPEC trata el host como variable libre y todo lo que se construye corre idéntico contra `supabase start`.

---

## 10. Glosario

| Término                    | Definición                                                                                                     |
| -------------------------- | -------------------------------------------------------------------------------------------------------------- |
| **Bulto**                  | Unidad de compra del proveedor (ej. bolsa 5 kg, caja 12 u).                                                    |
| **Pack**                   | Unidad de venta del negocio (ej. 1 kg fraccionado, 500 g).                                                     |
| **Curación de catálogo**   | Proceso por el cual el negocio decide qué subconjunto de productos del proveedor vende.                        |
| **Mapeo pack→bulto**       | Relación que indica cuántos packs se obtienen de un bulto.                                                     |
| **Snapshot del proveedor** | Copia en Supabase del catálogo del proveedor, confirmada por el admin.                                         |
| **Sincronización**         | Proceso de comparar la Sheet del proveedor con el snapshot y proponer cambios al admin.                        |
| **Consolidación**          | Proceso de sumar packs pedidos por los clientes y traducirlos a bultos a pedir al proveedor.                   |
| **Merma**                  | Porcentaje de producto que se pierde al fraccionar un bulto en packs.                                          |
| **Markup**                 | Porcentaje que se suma al costo del proveedor (por pack) para determinar el precio de venta.                   |
| **RLS**                    | Row Level Security de PostgreSQL/Supabase. Define por fila quién puede leer/escribir.                          |
| **JWT**                    | JSON Web Token. Credencial firmada que el frontend envía en cada request para probar que la sesión es válida.  |
| **Anon key**               | Clave pública de Supabase que usa el frontend. Solo puede lo que RLS permita al rol `anon`.                    |
| **Service role key**       | Clave secreta de Supabase que bypassa RLS. Solo se usa en serverless functions, nunca en el frontend.          |
| **MFA**                    | Multi-Factor Authentication. Segundo factor además de la contraseña (ej. código TOTP de Google Authenticator). |
| **SDD**                    | Spec-Driven Development: la especificación vive en el repo y es la fuente de verdad del desarrollo.            |

---

## Historial de cambios

| Versión | Fecha      | Autor | Cambios                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| ------- | ---------- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1.0     | 2026-04-23 | —     | Versión inicial                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| 1.1     | 2026-04-23 | —     | Proveedor único como entidad extensible. Catálogo como curación explícita. Flujo `/admin/sync-proveedor`. Snapshot `productos_proveedor`. Campos `precio_modo` y `markup_pct`. Tabla `sync_proveedor_logs`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| 1.2     | 2026-04-23 | —     | Nuevo capítulo §6 de seguridad y autenticación con políticas RLS detalladas, hardening, gestión de incidentes y checklist pre-producción. Tabla `admin_audit_log` para trazabilidad. Campos `ejecutado_por` y `generada_por` en logs y órdenes. Separación explícita entre cliente (sin auth) y admin (Supabase Auth). Nueva decisión abierta sobre MFA.                                                                                                                                                                                                                                                                                                                                                        |
| 1.3     | 2026-04-23 | —     | Cierre de 5 decisiones de §9 (markup 20% default editable, soft delete, imagen inicial desde Excel editable, MFA diferida a v1.1, sesión 1h+7d). `productos_negocio.id_producto_proveedor` marcada nullable para permitir seed del catálogo existente sin vínculo inmediato al proveedor. Fase 1 redefine la importación inicial: ahora carga desde `files/MM_productos_naturales.xlsx` (hoja `catalog`) a `productos_negocio`, reemplazando la carga desde la Sheet del proveedor.                                                                                                                                                                                                                             |
| 1.4     | 2026-04-23 | —     | La Sheet del proveedor es una lista humana no tabular. §4.1 `productos_proveedor`: nuevas columnas `nombre_base`, `nombre_original`, `presentacion`, `reemplaza_a`; `codigo_externo` pasa a ser sintético derivado de `(nombre_base, presentacion)`; `precio_bulto` nullable; estado gana valor `sin_precio`. §5.3.3: nueva acción manual de **fusión** `(nuevo, baja)` para cambios tipográficos del proveedor; se distingue "sin precio temporal" de "baja". §5.3.3.1 nuevo: documenta los 5 patrones de la Sheet que debe manejar el parser. §1.5: constatación de que la Sheet no es tabular. §8 Fase 2: estimación actualizada a 3–4 semanas.                                                              |
| 1.5     | 2026-04-24 | —     | Stack desacoplado del cloud de Supabase. §3.1: el "Backend / DB" pasa a ser el stack open-source de Supabase (Postgres + GoTrue + PostgREST + Studio) corriendo en Docker via `supabase start` para dev y CI. §3.1: la fila "Hosting" deja de recomendar Vercel y se difiere a §9.2. §3.2: diagrama de componentes ajustado para mostrar la pila autohosteada y "host por decidir" en el frontend. §9.2: nueva decisión abierta "Hosting de producción" con tres opciones contempladas (VPS único, frontend estático + backend separado, o reactivar Supabase Cloud). El cambio no requiere modificación de código: las 8 migraciones, las 3 RPCs y los 184 tests pgTAP ya corren contra el stack autohosteado. |
