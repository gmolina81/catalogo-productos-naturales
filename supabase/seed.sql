-- Seed para desarrollo local.
-- Se ejecuta después de todas las migraciones cuando corrés `supabase db reset`.
-- NO incluir datos reales del negocio acá; solo fixtures estables para tests manuales.

-- Proveedor único (New Garden). SPEC §1.5.
-- sheet_id corresponde a la URL pública compartida por el negocio.
insert into public.proveedores (nombre, sheet_id, sheet_range, contacto_whatsapp, contacto_email, activo)
values (
    'New Garden',
    '1O-zrDpH7-vKnegG38pm8u4qIoY9NySsJD2T8WGRjbtk',
    null,
    '1134632133',
    null,
    true
)
on conflict do nothing;

-- ====== Usuario admin de prueba (LOCAL/CI solamente) ======
-- Credenciales conocidas para tests de integración y E2E contra Supabase local.
-- En producción el admin se crea desde el dashboard de Supabase (otra cuenta, otro password).
-- Password: E2eAdminPass2026!  (cumple la política de SPEC §6.2)

-- Los campos `confirmation_token`, `recovery_token`, `email_change_token_new` y
-- `email_change` son text nullable sin default; GoTrue los escanea como string y
-- falla si son NULL. Hay que inicializarlos explícitamente en ''.
insert into auth.users (
    instance_id, id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    is_sso_user, is_anonymous,
    confirmation_token, recovery_token,
    email_change_token_new, email_change,
    created_at, updated_at
) values (
    '00000000-0000-0000-0000-000000000000',
    'aaaa1111-1111-1111-1111-111111111111',
    'authenticated', 'authenticated',
    'admin@test.local',
    crypt('E2eAdminPass2026!', gen_salt('bf', 10)),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    false, false,
    '', '', '', '',
    now(), now()
) on conflict (id) do nothing;

-- Identity row (Supabase moderna requiere una fila en auth.identities para
-- que `signInWithPassword` funcione con el provider 'email').
insert into auth.identities (
    id, user_id, identity_data, provider, provider_id,
    created_at, updated_at, last_sign_in_at
) values (
    gen_random_uuid(),
    'aaaa1111-1111-1111-1111-111111111111',
    jsonb_build_object(
        'sub', 'aaaa1111-1111-1111-1111-111111111111',
        'email', 'admin@test.local',
        'email_verified', true
    ),
    'email',
    'admin@test.local',
    now(), now(), now()
) on conflict (provider, provider_id) do nothing;
