# Códigos de error

Estos códigos son para soporte interno. La app debe mostrar al usuario un mensaje breve y accionable, más el código. Los detalles técnicos se revisan en logs o en backend.

| Código | Mensaje usuario | Causa técnica | Acción soporte |
| --- | --- | --- | --- |
| AUTH-LOGIN | No pudimos iniciar sesión. Inténtalo nuevamente. | Falló el inicio de sesión Google/Firebase o una operación inicial relacionada. | Revisar logs de Firebase Auth y configuración Google Sign-In. |
| AUTH-SIGNOUT | No pudimos cerrar sesión correctamente. | Falló el cierre de sesión local/Firebase/Google. | Pedir reinicio de app y revisar logs del dispositivo. |
| AUTH-RESTORE | No pudimos validar tu sesión. Inténtalo nuevamente. | Falló la restauración de sesión API por una excepción no clasificada. | Revisar logs de app y respuesta de `/api/auth/firebase`. |
| AUTH-401 | Tu sesión venció. Inicia sesión nuevamente. | La API devolvió 401 en una solicitud protegida. | Verificar expiración del JWT interno o revocación de sesión. |
| AUTH-401-FB | No pudimos validar tu sesión. Inicia sesión nuevamente. | FastAPI rechazó el Firebase ID Token. | Confirmar service account Firebase Admin, project_id y validación de token. |
| AUTH-403 | Tu cuenta no tiene permiso para usar esta aplicación. Comunícate con el administrador. | La API devolvió 403 sin causa específica mapeada. | Revisar permisos del usuario en backend. |
| AUTH-403-DNI | Tu usuario aún no está habilitado para marcar asistencia. Comunícate con el administrador. | No existe DNI local para enviarlo como `emp_code`. | Crear/verificar `dni_by_email/{correo}` en Firestore con campo `dni`. |
| AUTH-403-EMP | Tu usuario aún no está habilitado para marcar asistencia. Comunícate con el administrador. | La API indica que el usuario no tiene `emp_code` asociado. | Asociar `emp_code`/DNI al usuario en la base del backend o corregir creación automática. |
| AUTH-RESP | No pudimos iniciar tu sesión en el servidor de asistencia. Inténtalo nuevamente. | `/api/auth/firebase` devolvió un formato inesperado. | Verificar contrato de respuesta: `access_token`, `token_type`, `expires_in`. |
| AUTH-NO-TOKEN | No pudimos iniciar tu sesión en el servidor de asistencia. Inténtalo nuevamente. | `/api/auth/firebase` no devolvió `access_token`. | Revisar respuesta del endpoint de autenticación. |
| API-503 | No pudimos conectar con el servidor de asistencia. Inténtalo nuevamente en unos minutos. | Servidor no disponible, timeout/proxy o HTTP 502/503/504/521-524/530. | Revisar disponibilidad de FastAPI, DNS, proxy o Cloudflare. |
| MARK-001 | No pudimos registrar tu marcación. Inténtalo nuevamente. | Error no clasificado al registrar marcación. | Revisar logs del dispositivo y backend. |
| MARK-403 | Tu usuario no tiene permiso para registrar asistencia. Comunícate con el administrador. | La API rechazó la marcación con 403. | Revisar permisos/estado del usuario en backend. |
| MARK-{HTTP} | No pudimos registrar tu marcación. Inténtalo nuevamente. | La API devolvió un HTTP no exitoso al marcar. | Revisar status/body del backend para ese intento. |
| LAST-{HTTP} | No pudimos consultar tu última marcación. Inténtalo nuevamente. | La API devolvió un HTTP no exitoso al consultar última marcación. | Revisar endpoint `/api/logs/ultimo-registro/{emp_code}`. |
| DASH-403 | Tu usuario no tiene permiso para ver el panel de asistencia. Comunícate con el administrador. | La API rechazó `/api/dashboard/me` con 403. | Revisar permisos/estado del usuario en backend. |
| DASH-RESP | No pudimos cargar tu panel de asistencia. Inténtalo nuevamente. | La respuesta de `/api/dashboard/me` no tuvo el formato esperado. | Verificar schema JSON del endpoint. |
| DASH-{HTTP} | No pudimos cargar tu panel de asistencia. Inténtalo nuevamente. | La API devolvió un HTTP no exitoso al cargar dashboard. | Revisar endpoint `/api/dashboard/me?month=YYYY-MM`. |
