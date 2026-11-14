# Backend Supabase de Seuz

- `sql/01_esquema.sql`: crear tablas, políticas RLS, validaciones de inscripciones y auditoría.
- `sql/02_primer_superadmin.sql`: asignar el primer usuario de Supabase Auth como superadministrador.
- `supabase/functions/gestionar-usuarios/index.ts`: función de creación/edición de cuentas y contraseñas; requiere actor autorizado.
- `supabase/config.toml`: mantiene la validación JWT activa.

Para el procedimiento completo, abre `../LEEME_PRIMERO.md`.
