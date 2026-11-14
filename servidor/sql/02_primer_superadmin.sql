-- PASO 1: En Supabase > Authentication > Users > Add user,
-- crea MANUALMENTE tu primera cuenta con correo y contraseña.
-- PASO 2: Reemplaza los DOS campos de abajo por el correo real que creaste.
-- PASO 3: Ejecuta el SQL. Úsalo únicamente para el primer superadministrador.
insert into public.perfiles (id, correo, nombres, apellidos, rol, codigo, activo)
select id, email, 'Super', 'Administrador', 'superadministrador', 'SEUZ-ADMIN-001', true
from auth.users where lower(email)=lower('TU_CORREO@EJEMPLO.COM')
on conflict(id) do update set rol='superadministrador', activo=true;
-- Debería aparecer una fila:
select correo, rol, activo from public.perfiles
where lower(correo)=lower('TU_CORREO@EJEMPLO.COM');
