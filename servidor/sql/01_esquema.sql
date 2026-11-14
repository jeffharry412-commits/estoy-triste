-- SEUZ | Esquema inicial para un proyecto NUEVO de Supabase
-- Ejecútalo una sola vez en SQL Editor. No copies claves privadas en el frontend.
create extension if not exists pgcrypto;

create table if not exists public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  correo text not null unique,
  nombres text not null,
  apellidos text not null,
  rol text not null check (rol in ('superadministrador','administracion','docente','estudiante')),
  codigo text unique,
  telefono text,
  carrera text,
  especialidad text,
  fecha_ingreso date,
  estado_academico text not null default 'Activo' check (estado_academico in ('Activo','Inactivo','Egresado','Retirado')),
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

create table if not exists public.cursos (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  descripcion text,
  carrera text,
  semestre integer not null default 1 check (semestre between 1 and 20),
  creditos integer not null default 1 check (creditos between 0 and 30),
  docente_id uuid references public.perfiles(id) on delete set null,
  cupo_maximo integer not null default 30 check (cupo_maximo between 1 and 1000),
  estado text not null default 'activo' check (estado in ('activo','inactivo')),
  creado_en timestamptz not null default now()
);

create table if not exists public.inscripciones (
  id uuid primary key default gen_random_uuid(),
  estudiante_id uuid not null references public.perfiles(id) on delete restrict,
  curso_id uuid not null references public.cursos(id) on delete restrict,
  estado text not null default 'activa' check (estado in ('activa','retirada','finalizada')),
  inscrito_en timestamptz not null default now(),
  unique(estudiante_id, curso_id)
);

create table if not exists public.calificaciones (
  id uuid primary key default gen_random_uuid(),
  inscripcion_id uuid not null unique references public.inscripciones(id) on delete restrict,
  nota1 numeric(5,2) check (nota1 between 0 and 100),
  nota2 numeric(5,2) check (nota2 between 0 and 100),
  nota3 numeric(5,2) check (nota3 between 0 and 100),
  nota4 numeric(5,2) check (nota4 between 0 and 100),
  total numeric(6,2) generated always as (
    coalesce(nota1,0)+coalesce(nota2,0)+coalesce(nota3,0)+coalesce(nota4,0)
  ) stored,
  promedio numeric(5,2) generated always as (
    case when nota1 is null and nota2 is null and nota3 is null and nota4 is null then null
    else round((coalesce(nota1,0)+coalesce(nota2,0)+coalesce(nota3,0)+coalesce(nota4,0))/4.0, 2)
    end
  ) stored,
  actualizado_por uuid references public.perfiles(id) on delete set null,
  actualizado_en timestamptz not null default now()
);

create table if not exists public.historial_calificaciones (
  id bigint generated always as identity primary key,
  calificacion_id uuid not null,
  inscripcion_id uuid not null,
  accion text not null check (accion in ('INSERT','UPDATE','DELETE')),
  anterior jsonb,
  nuevo jsonb,
  modificado_por uuid,
  fecha timestamptz not null default now()
);

create index if not exists idx_cursos_docente on public.cursos(docente_id);
create index if not exists idx_inscripciones_curso on public.inscripciones(curso_id, estado);
create index if not exists idx_inscripciones_estudiante on public.inscripciones(estudiante_id);
create index if not exists idx_historial_inscripcion on public.historial_calificaciones(inscripcion_id);

-- Funciones de autorización: SECURITY DEFINER evita recursión en las políticas RLS.
create or replace function public.seuz_activo() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo);
$$;
create or replace function public.seuz_rol(r text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol=r);
$$;
create or replace function public.seuz_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('superadministrador','administracion'));
$$;
create or replace function public.seuz_docente_de_estudiante(s uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.inscripciones i join public.cursos c on c.id=i.curso_id
    where i.estudiante_id=s and c.docente_id=(select auth.uid()) and i.estado='activa');
$$;
create or replace function public.seuz_docente_de_mi_curso(d uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.inscripciones i join public.cursos c on c.id=i.curso_id
    where i.estudiante_id=(select auth.uid()) and c.docente_id=d and i.estado='activa');
$$;
create or replace function public.seuz_ver_curso(c uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.seuz_admin() or exists(
    select 1 from public.cursos x where x.id=c and x.docente_id=(select auth.uid()))
    or exists(select 1 from public.inscripciones i where i.curso_id=c and i.estudiante_id=(select auth.uid()));
$$;
create or replace function public.seuz_ver_inscripcion(i uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.seuz_admin() or exists(select 1 from public.inscripciones x
    left join public.cursos c on c.id=x.curso_id where x.id=i and
    (x.estudiante_id=(select auth.uid()) or c.docente_id=(select auth.uid())));
$$;
create or replace function public.seuz_editar_nota(i uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.seuz_admin() or exists(select 1 from public.inscripciones x
    join public.cursos c on c.id=x.curso_id where x.id=i and c.docente_id=(select auth.uid())
    and x.estado='activa' and public.seuz_rol('docente'));
$$;

-- Solo un docente auténtico y activo puede estar asignado a un curso.
create or replace function public.seuz_validar_docente() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.docente_id is not null and not exists (
    select 1 from public.perfiles p where p.id=new.docente_id and p.rol='docente' and p.activo
  ) then raise exception 'El docente asignado debe existir y estar activo'; end if;
  if tg_op='UPDATE' and new.cupo_maximo<old.cupo_maximo and
    new.cupo_maximo < (select count(*) from public.inscripciones where curso_id=new.id and estado='activa')
  then raise exception 'El cupo no puede ser menor a las inscripciones activas'; end if;
  return new;
end;
$$;
create trigger trg_validar_docente before insert or update on public.cursos
for each row execute function public.seuz_validar_docente();

-- Bloqueo de curso para evitar sobrecupos durante inscripciones simultáneas.
create or replace function public.seuz_validar_inscripcion() returns trigger
language plpgsql set search_path = '' as $$
declare maximo integer; ocupados integer;
begin
  if not exists (select 1 from public.perfiles p where p.id=new.estudiante_id and p.rol='estudiante' and p.activo) then
    raise exception 'El estudiante debe existir y estar activo'; end if;
  if new.estado='activa' and (tg_op='INSERT' or old.estado is distinct from 'activa'
    or old.curso_id is distinct from new.curso_id) then
    select cupo_maximo into maximo from public.cursos
      where id=new.curso_id and estado='activo' for update;
    if maximo is null then raise exception 'El curso no está activo'; end if;
    select count(*) into ocupados from public.inscripciones
      where curso_id=new.curso_id and estado='activa' and id is distinct from new.id;
    if ocupados >= maximo then raise exception 'Este curso ya no tiene cupos disponibles'; end if;
  end if;
  return new;
end;
$$;
create trigger trg_validar_inscripcion before insert or update on public.inscripciones
for each row execute function public.seuz_validar_inscripcion();

create or replace function public.seuz_auditar_nota() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op='DELETE' then
    insert into public.historial_calificaciones(calificacion_id,inscripcion_id,accion,anterior,nuevo,modificado_por)
    values(old.id,old.inscripcion_id,'DELETE',to_jsonb(old),null,(select auth.uid()));
    return old;
  end if;
  new.actualizado_en = now();
  new.actualizado_por = (select auth.uid());
  if tg_op='INSERT' or row(new.nota1,new.nota2,new.nota3,new.nota4) is distinct from row(old.nota1,old.nota2,old.nota3,old.nota4) then
    insert into public.historial_calificaciones(calificacion_id,inscripcion_id,accion,anterior,nuevo,modificado_por)
    values(new.id,new.inscripcion_id,tg_op,case when tg_op='UPDATE' then to_jsonb(old) else null end,
      to_jsonb(new),(select auth.uid()));
  end if;
  return new;
end;
$$;
create trigger trg_auditar_nota before insert or update or delete on public.calificaciones
for each row execute function public.seuz_auditar_nota();

alter table public.perfiles enable row level security;
alter table public.cursos enable row level security;
alter table public.inscripciones enable row level security;
alter table public.calificaciones enable row level security;
alter table public.historial_calificaciones enable row level security;

create policy "Perfiles visibles segun rol" on public.perfiles for select to authenticated
using (public.seuz_activo() and (
  id=(select auth.uid()) or public.seuz_admin() or
  (rol='estudiante' and public.seuz_rol('docente') and public.seuz_docente_de_estudiante(id)) or
  (rol='docente' and public.seuz_rol('estudiante') and public.seuz_docente_de_mi_curso(id))
));
-- Escritura de perfiles SOLO mediante función servidor privilegiada y verificada.

create policy "Consultar cursos autorizados" on public.cursos for select to authenticated
using (public.seuz_activo() and public.seuz_ver_curso(id));
create policy "Crear cursos administracion" on public.cursos for insert to authenticated
with check (public.seuz_admin());
create policy "Editar cursos administracion" on public.cursos for update to authenticated
using (public.seuz_admin()) with check (public.seuz_admin());
create policy "Eliminar cursos administracion" on public.cursos for delete to authenticated
using (public.seuz_admin());

create policy "Consultar inscripciones autorizadas" on public.inscripciones for select to authenticated
using (public.seuz_activo() and public.seuz_ver_inscripcion(id));
create policy "Inscribir administracion" on public.inscripciones for insert to authenticated
with check (public.seuz_admin());
create policy "Editar inscripcion administracion" on public.inscripciones for update to authenticated
using (public.seuz_admin()) with check (public.seuz_admin());
create policy "Eliminar inscripcion administracion" on public.inscripciones for delete to authenticated
using (public.seuz_admin());

create policy "Consultar calificaciones autorizadas" on public.calificaciones for select to authenticated
using (public.seuz_activo() and public.seuz_ver_inscripcion(inscripcion_id));
create policy "Crear notas autorizadas" on public.calificaciones for insert to authenticated
with check (public.seuz_activo() and public.seuz_editar_nota(inscripcion_id));
create policy "Editar notas autorizadas" on public.calificaciones for update to authenticated
using (public.seuz_activo() and public.seuz_editar_nota(inscripcion_id))
with check (public.seuz_activo() and public.seuz_editar_nota(inscripcion_id));
create policy "Borrar notas administracion" on public.calificaciones for delete to authenticated
using (public.seuz_admin());

create policy "Consultar historial notas autorizado" on public.historial_calificaciones for select to authenticated
using (public.seuz_activo() and public.seuz_ver_inscripcion(inscripcion_id));

-- Se concede acceso SQL de lectura/escritura únicamente con las políticas anteriores.
revoke all on public.perfiles, public.cursos, public.inscripciones,
  public.calificaciones, public.historial_calificaciones from anon;
grant select on public.perfiles, public.cursos, public.inscripciones,
  public.calificaciones, public.historial_calificaciones to authenticated;
grant insert, update, delete on public.cursos, public.inscripciones, public.calificaciones to authenticated;
grant all on public.perfiles, public.cursos, public.inscripciones,
  public.calificaciones, public.historial_calificaciones to service_role;
grant usage, select on sequence public.historial_calificaciones_id_seq to service_role;
revoke all on function public.seuz_activo(), public.seuz_rol(text), public.seuz_admin(),
 public.seuz_docente_de_estudiante(uuid), public.seuz_docente_de_mi_curso(uuid),
 public.seuz_ver_curso(uuid), public.seuz_ver_inscripcion(uuid), public.seuz_editar_nota(uuid) from public;
grant execute on function public.seuz_activo(), public.seuz_rol(text), public.seuz_admin(),
 public.seuz_docente_de_estudiante(uuid), public.seuz_docente_de_mi_curso(uuid),
 public.seuz_ver_curso(uuid), public.seuz_ver_inscripcion(uuid), public.seuz_editar_nota(uuid) to authenticated, service_role;
