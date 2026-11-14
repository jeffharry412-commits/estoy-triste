# SEUZ — APK Android con conexión a base de datos Supabase

**Archivo de instalación:** `Seuz_Nube_BD.apk`

Esta entrega convierte la versión Android local de Seuz en una versión **preparada para conectarse a una única base de datos Supabase**. Los accesos de **superadministrador, administración, docente y estudiante**, los cursos, las inscripciones y las calificaciones (4 unidades) se consultan y guardan mediante HTTPS en el proyecto que configures.

**Estado real de la entrega:** la APK está construida y firmada. Se validaron su estructura, el permiso de Internet y la sintaxis JavaScript, y se probaron mediante respuestas simuladas las operaciones de inicio de sesión, lectura, creación, edición, eliminación, cambio de contraseña y renovación de sesión. **No está enlazada a ninguna base de datos real ni se ha probado físicamente en Android**. Para usarla entre varios celulares es obligatorio completar la configuración detallada abajo y comprobar los permisos antes de ingresar información auténtica.

## 0. Antes de instalar: respaldar lo que ya tienes

La nueva APK tiene el mismo identificador Android que la versión anterior (`com.seuz.academico`), pero una firma diferente. Android puede pedir **desinstalar la aplicación anterior** para poder instalar esta. **Desinstalar borra la información local** que tenía Seuz.

1. Abre la aplicación anterior antes de desinstalarla.
2. Ingresa como superadministrador y usa la sección **Configuración → Descargar respaldo** si está disponible; guarda el archivo fuera de la app.
3. Comprueba que el respaldo se haya guardado. Conserva una copia segura: puede contener información personal.
4. Después instala la nueva versión.

**Los datos guardados en la app anterior NO se migran solos a Supabase.** El respaldo local no es un importador automático de los datos de nube; se necesita un proceso de migración independiente. Si no tienes copia o tienes datos importantes, **no desinstales la aplicación anterior**.

## 1. Crear la base de datos del colegio

1. Entra en https://supabase.com/dashboard e inicia sesión o crea tu cuenta.
2. Crea un **proyecto nuevo**; selecciona una región y contraseña privada de PostgreSQL. Esa contraseña **NUNCA se ingresa en la APK**.
3. En Supabase abre **SQL Editor → New query** y ejecuta el archivo `servidor/sql/01_esquema.sql`. Debe ejecutarse **solo una vez en un proyecto nuevo**. Crea las tablas, las restricciones y la seguridad por filas (RLS).
4. En **Authentication → Providers → Email**, desactiva el registro público si solo el personal administrativo debe crear usuarios.
5. En **Authentication → Users → Add user**, crea tu primera cuenta como superadministrador con correo institucional y contraseña segura. Si ofrece confirmar el correo de forma administrativa, confírmalo.
6. Abre el archivo `servidor/sql/02_primer_superadmin.sql` en un editor de texto. Reemplaza **las dos apariciones** de `TU_CORREO@EJEMPLO.COM` por el correo de la cuenta del paso anterior. Ejecuta ese contenido en **SQL Editor**.
7. Comprueba que el SELECT final indique el rol `superadministrador` y `activo=true`.

## 2. Publicar la función que crea usuarios y contraseñas

La APK **nunca** debe contener una clave administrativa de Supabase. Por eso, para que el administrador pueda crear cuentas o restablecer contraseñas de terceros se debe publicar la función protegida `gestionar-usuarios`.

En una computadora con Node.js instalado, abre la terminal dentro de la carpeta `servidor` y ejecuta:

```bash
npm install --save-dev supabase
npx supabase login
npx supabase functions deploy gestionar-usuarios --project-ref TU_PROJECT_REF
```

Reemplaza `TU_PROJECT_REF` por el ID de tu proyecto (la parte que aparece antes de `.supabase.co`). La función está en `servidor/supabase/functions/gestionar-usuarios/index.ts`; la configuración está en `servidor/supabase/config.toml` y requiere JWT autenticado. Es posible que la CLI solicite hacer `npx supabase link --project-ref TU_PROJECT_REF`.

**No copies claves `secret`, `service_role` ni contraseñas privadas dentro del APK o del archivo HTML.**

## 3. Configurar la APK en tu celular

1. Instala `Seuz_Nube_BD.apk` en Android (puede ser necesario desinstalar la versión previa **solo después de hacer el respaldo**).
2. Al abrir Seuz, verás **Conectar base de datos**.
3. En Supabase localiza la **Project URL** (de la forma `https://TU-ID.supabase.co`) y la **publishable key** (`sb_publishable_...`) en Project Settings / API Keys. También acepta la antigua `anon` pública.
4. Escribe estos **dos valores públicos** en la pantalla inicial de Seuz y presiona **Guardar y conectar**.
5. Inicia sesión con el correo y la contraseña del primer superadministrador que creaste en Supabase.
6. Ve a **Usuarios** y crea cuentas de administración, docentes y estudiantes. Cada uno iniciará sesión con el mismo proyecto Supabase desde su propio teléfono.
7. Para cambiar de proyecto: cierra sesión y toca **Cambiar conexión de Supabase**.

## 4. Cómo comprobar que realmente se sincronizan

1. Instala la APK en **dos celulares Android**.
2. Configura en ambos exactamente la misma URL y clave **pública**.
3. Inicia sesión con la cuenta de superadministrador, crea una cuenta docente y otra de estudiante.
4. Crea un curso, asigna al docente, inscribe al estudiante y registra las **cuatro notas**.
5. En el segundo celular, inicia sesión como el estudiante. Deberá ver solamente sus cursos y notas.
6. Desde administración, comprueba que los registros se vean en ambos celulares después de actualizar, y que un alumno no pueda consultar información de otro.

## Qué se guarda en Supabase

- Usuarios: autenticación y contraseñas mediante **Supabase Auth**, no contraseñas en texto plano.
- Perfiles: código, nombre, apellido, correo, rol y demás datos permitidos.
- Cursos: asignación de docentes, descripción, cupos y estado.
- Inscripciones: registro por estudiante y curso, con validación de duplicados y cupos.
- Calificaciones: unidad 1, 2, 3 y 4, total y promedio; historial de cambios.
- Reportes: consultas según permisos y generación de CSV para copiar al portapapeles. La exportación automática a Excel/PDF de escritorio no está garantizada en este WebView Android.

## Advertencias importantes

- Esta es una compilación de **prueba** de la app Android existente con WebView. No constituye una auditoría de seguridad ni una app aprobada para producción. Se debe probar en dispositivos reales y con una base de pruebas antes de ingresar datos de menores de edad.
- El acceso depende de **Internet** y del proyecto Supabase que configures. No ofrece trabajo sin conexión ni sincronización en segundo plano.
- Las filas visibles se controlan con políticas **RLS en la base de datos**, no únicamente escondiendo botones en el HTML. Prueba los cuatro roles con datos de demostración.
- Se guarda la sesión de usuario en el almacenamiento local del WebView; protege el celular con bloqueo de pantalla y activa copias de seguridad seguras en Supabase.
- La clave pública Supabase es visible por diseño; la seguridad depende de Auth, permisos, RLS y la función de servidor.
- La APK está firmada con un **certificado nuevo de prueba**, distinto de la APK anterior; para actualizaciones futuras necesita conservar la misma clave de firma.

## Fuentes oficiales

- Supabase Auth: https://supabase.com/docs/guides/auth
- Supabase REST API: https://supabase.com/docs/guides/api
- Supabase RLS: https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase Edge Functions: https://supabase.com/docs/guides/functions/auth
