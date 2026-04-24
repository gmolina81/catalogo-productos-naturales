/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string
  readonly VITE_SUPABASE_ANON_KEY: string
  readonly VITE_PROVIDER_SHEET_ID: string
  readonly VITE_BUSINESS_WHATSAPP: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
