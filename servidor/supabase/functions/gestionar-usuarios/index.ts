// Función Supabase Edge: jamás exponer la clave de servicio al navegador.
// Requiere cuenta autenticada; autorización comprobada CONTRA LA BD.
import { withSupabase } from 'npm:@supabase/server@1';

type Entrada = Record<string, unknown>;
const txt = (v: unknown, max = 180) => typeof v === 'string' ? v.trim().slice(0,max) : '';
const error = (mensaje: string, codigo = 400) => Response.json({ error: mensaje }, { status: codigo });
const roles = ['superadministrador','administracion','docente','estudiante'];

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') return error('Solo POST',405);
    let body: Entrada;
    try { body = await req.json(); } catch { return error('JSON no válido'); }
    // `withSupabase` validó criptográficamente el JWT antes de este handler.
    const actorId = ctx.userClaims?.id;
    if (!actorId) return error('Sesión inválida',401);
    const { data: solicitante, error: actorError } = await ctx.supabaseAdmin
      .from('perfiles').select('id,rol,activo').eq('id',actorId).single();
    if (actorError || !solicitante?.activo || !['superadministrador','administracion'].includes(solicitante.rol)) {
      return error('No tienes permiso para administrar usuarios',403);
    }
    const esSuper = solicitante.rol === 'superadministrador';
    const accion = txt(body.accion,30);
    const id = txt(body.id,80);
    const rol = txt(body.rol,30);
    const permitido = (r: string) => roles.includes(r) && (esSuper || ['estudiante','docente'].includes(r));

    if (accion === 'crear') {
      const correo = txt(body.correo,240).toLowerCase();
      const clave = typeof body.contrasena === 'string' ? body.contrasena : '';
      const nombres = txt(body.nombres,120), apellidos = txt(body.apellidos,120);
      if (!permitido(rol)) return error('No está autorizado para crear ese rol',403);
      if (!/^\S+@\S+\.\S+$/.test(correo) || !nombres || !apellidos) return error('Correo, nombres y apellidos son obligatorios');
      if (clave.length < 10 || clave.length > 128) return error('La contraseña debe tener entre 10 y 128 caracteres');
      const { data: creado, error: crearError } = await ctx.supabaseAdmin.auth.admin.createUser({
        email: correo, password: clave, email_confirm: true,
      });
      if (crearError || !creado?.user) return error(crearError?.message || 'No se pudo crear la cuenta');
      const perfil = {
        id: creado.user.id, correo, nombres, apellidos, rol,
        codigo: txt(body.codigo,50) || null, telefono: txt(body.telefono,40) || null,
        carrera: txt(body.carrera,120) || null, especialidad: txt(body.especialidad,120) || null,
        fecha_ingreso: txt(body.fecha_ingreso,12) || null,
        estado_academico: txt(body.estado_academico,20) || 'Activo', activo: true,
      };
      const { error: perfilError } = await ctx.supabaseAdmin.from('perfiles').insert(perfil);
      if (perfilError) {
        await ctx.supabaseAdmin.auth.admin.deleteUser(creado.user.id);
        return error('No se creó el perfil: ' + perfilError.message);
      }
      return Response.json({ ok: true, id: creado.user.id, correo });
    }

    if (!id) return error('Falta el identificador de la cuenta');
    const { data: destino } = await ctx.supabaseAdmin.from('perfiles')
      .select('id,rol,activo,correo').eq('id',id).maybeSingle();
    if (!destino) return error('Usuario no encontrado',404);
    if (!esSuper && !['estudiante','docente'].includes(destino.rol)) return error('No tienes permiso sobre este usuario',403);

    if (accion === 'actualizar') {
      const nuevoRol = rol || destino.rol;
      if (!permitido(nuevoRol)) return error('No puedes asignar ese rol',403);
      if (id === actorId && (nuevoRol !== destino.rol || body.activo === false)) {
        return error('No puedes desactivar tu propia cuenta ni quitarte tu rol');
      }
      if (nuevoRol !== destino.rol) {
        if (destino.rol === 'docente') {
          const { count } = await ctx.supabaseAdmin.from('cursos').select('id',{count:'exact',head:true}).eq('docente_id',id);
          if (count && count > 0) return error('No puedes cambiar el rol: tiene cursos asignados. Reasígnalos primero.');
        }
        if (destino.rol === 'estudiante') {
          const { count } = await ctx.supabaseAdmin.from('inscripciones').select('id',{count:'exact',head:true}).eq('estudiante_id',id);
          if (count && count > 0) return error('No puedes cambiar el rol: tiene inscripciones académicas.');
        }
      }
      const nombres = txt(body.nombres,120), apellidos = txt(body.apellidos,120);
      if (!nombres || !apellidos) return error('Nombres y apellidos son obligatorios');
      const nuevoCorreo = txt(body.correo,240).toLowerCase();
      if (!/^\S+@\S+\.\S+$/.test(nuevoCorreo)) return error('Correo electrónico no válido');
      const cambioCorreo = nuevoCorreo !== destino.correo.toLowerCase();
      if (cambioCorreo) {
        const { error: cambioAuthError } = await ctx.supabaseAdmin.auth.admin.updateUserById(id,{
          email:nuevoCorreo, email_confirm:true,
        });
        if (cambioAuthError) return error(cambioAuthError.message);
      }
      const cambios = {
        nombres, apellidos, rol: nuevoRol, correo: nuevoCorreo,
        codigo: txt(body.codigo,50) || null, telefono: txt(body.telefono,40) || null,
        carrera: txt(body.carrera,120) || null, especialidad: txt(body.especialidad,120) || null,
        fecha_ingreso: txt(body.fecha_ingreso,12) || null,
        estado_academico: txt(body.estado_academico,20) || 'Activo',
        activo: typeof body.activo === 'boolean' ? body.activo : destino.activo,
      };
      const { error: err } = await ctx.supabaseAdmin.from('perfiles').update(cambios).eq('id',id);
      if (err) {
        if (cambioCorreo) await ctx.supabaseAdmin.auth.admin.updateUserById(id,{
          email: destino.correo, email_confirm:true,
        });
        return error('No se pudo guardar el perfil: ' + err.message);
      }
      return Response.json({ ok:true });
    }
    if (accion === 'contrasena') {
      if (id===actorId) return error('Cambia tu contraseña personal desde Mi perfil');
      const clave = typeof body.contrasena === 'string' ? body.contrasena : '';
      if (clave.length < 10 || clave.length > 128) return error('La contraseña debe tener entre 10 y 128 caracteres');
      const { error: err } = await ctx.supabaseAdmin.auth.admin.updateUserById(id, {password:clave});
      if (err) return error(err.message);
      return Response.json({ok:true});
    }
    return error('Acción no admitida');
  }),
};
