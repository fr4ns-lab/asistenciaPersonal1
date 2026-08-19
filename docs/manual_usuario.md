# Manual de Usuario - SalleTime

**Aplicacion:** SalleTime - Registro de asistencia  
**Version:** [Completar con la version publicada]  
**Fecha de actualizacion:** [Completar]  
**Soporte:** [Correo o canal de soporte]

---

## 1. Objetivo

SalleTime permite registrar la asistencia desde un dispositivo movil, consultar la ultima marcacion y revisar el resumen de asistencia del periodo.

La aplicacion utiliza la cuenta institucional para identificar al usuario. Las horas, las marcaciones y los indicadores de asistencia son proporcionados por el sistema institucional.

---

## 2. Antes de empezar

Antes de usar la aplicacion, verifica lo siguiente:

- Tener una cuenta institucional activa con dominio `@lasalle.edu.pe`.
- Tener conexion a Internet.
- Mantener actualizada la fecha y hora automaticas del dispositivo.
- Permitir el acceso a la ubicacion cuando la aplicacion lo solicite, si la marcacion de tu cuenta requiere validacion de ubicacion.
- Tener el DNI asociado a tu cuenta institucional en el sistema de asistencia.

> **Importante:** No compartas tu cuenta institucional ni permitas que otra persona realice marcaciones en tu nombre.

---

## 3. Inicio de sesion

1. Abre SalleTime.
2. Pulsa **Iniciar sesion con Google**.
3. Selecciona tu cuenta institucional `@lasalle.edu.pe`.
4. Espera mientras la aplicacion valida tu acceso.

La primera vez que ingreses, la aplicacion mostrara la pantalla de autorizacion para el tratamiento de datos personales y uso de ubicacion.

5. Lee la autorizacion.
6. Marca la casilla de aceptacion.
7. Pulsa **Aceptar y continuar**.

**Resultado esperado:** se abre la pantalla **Registro**.

**[Insertar captura 1: pantalla de inicio de sesion]**

**[Insertar captura 2: autorizacion de datos personales]**

### Si no puedes iniciar sesion

- Confirma que seleccionaste una cuenta institucional.
- Verifica tu conexion a Internet.
- Cierra la aplicacion e intentalo otra vez.
- Si aparece un mensaje indicando que tu usuario no esta habilitado o no tiene DNI asociado, comunicate con soporte.

---

## 4. Navegacion principal

En la parte inferior encontraras tres secciones:

| Seccion | Uso |
| --- | --- |
| **Registro** | Registrar asistencia y consultar la ultima marcacion. |
| **Panel** | Consultar el resumen de asistencia por mes. |
| **Perfil** | Ver los datos de la cuenta y cerrar sesion. |

Puedes cambiar de seccion en cualquier momento sin cerrar la aplicacion.

**[Insertar captura 3: menu inferior con Registro, Panel y Perfil]**

---

## 5. Registrar asistencia

### 5.1 Revisar el estado antes de marcar

En la seccion **Registro** se muestra:

- Tu nombre, correo institucional y DNI asociado.
- La **Hora actual**, sincronizada para el registro de asistencia.
- El estado de ubicacion, cuando corresponde.
- La tarjeta **Ultima marcacion**.
- El boton **Registrar marcacion**.

Antes de marcar, espera que la hora se muestre correctamente. Si aparece el mensaje **Sin sincronizacion con servidor**, espera unos segundos y verifica tu conexion a Internet.

**[Insertar captura 4: pantalla Registro lista para marcar]**

### 5.2 Cuando se requiere ubicacion

Si tu cuenta requiere validacion de ubicacion, la aplicacion mostrara uno de estos estados:

| Estado | Que significa | Que hacer |
| --- | --- | --- |
| **Dentro del perimetro** | Tu ubicacion es valida para registrar. | Pulsa **Registrar marcacion**. |
| **Verificando ubicacion** | La aplicacion esta esperando una ubicacion valida. | Espera unos segundos o actualiza la ubicacion. |
| **Fuera del perimetro** | Estas fuera del area permitida. | Acercate al lugar autorizado; el boton permanecera deshabilitado. |
| GPS desactivado | El dispositivo no puede obtener tu ubicacion. | Activa el GPS y concede el permiso de ubicacion. |

Si necesitas actualizar la ubicacion, utiliza el boton de actualizar que aparece en la tarjeta de estado.

**[Insertar captura 5: estado Dentro del perimetro]**

**[Insertar captura 6: estado Fuera del perimetro o GPS desactivado]**

### 5.3 Marcacion autorizada sin validacion de ubicacion

Algunas cuentas pueden mostrar el mensaje:

> **Marcacion autorizada sin validacion de ubicacion.**

En ese caso, la aplicacion permite registrar sin comprobar el perimetro GPS. Esta condicion es definida por la institucion; no se configura desde el dispositivo.

### 5.4 Realizar la marcacion

1. Ingresa a **Registro**.
2. Comprueba que la hora este sincronizada.
3. Si se requiere ubicacion, confirma que el estado indique **Dentro del perimetro**.
4. Pulsa **Registrar marcacion**.
5. Espera la confirmacion en pantalla.

No cierres la aplicacion mientras aparezca el mensaje **Registrando...**.

**Resultado esperado:** aparece una confirmacion verde de registro exitoso. La tarjeta **Ultima marcacion** se actualiza con la informacion del servidor.

**[Insertar captura 7: confirmacion de marcacion exitosa]**

### 5.5 Ultima marcacion

La tarjeta **Ultima marcacion** muestra la hora y fecha de la marcacion mas reciente devuelta por el sistema de asistencia. Se actualiza al abrir la pantalla y despues de una marcacion exitosa.

Si no hay registros disponibles para mostrar, aparecera `--:--:--`.

> La aplicacion no decide si una marcacion es entrada o salida. Esa clasificacion y las horas oficiales son determinadas por el sistema institucional.

---

## 6. Consultar el Panel de asistencia

1. Pulsa **Panel** en el menu inferior.
2. Selecciona el mes que deseas consultar.
3. Espera la carga de la informacion.

El Panel muestra informacion calculada por el sistema institucional. Los valores pueden actualizarse cuando se registren nuevas marcaciones o se procese la asistencia.

**[Insertar captura 8: Panel de asistencia con selector de mes]**

### 6.1 Indicadores del Panel

| Indicador | Significado |
| --- | --- |
| **Dias marcados** | Dias programados, hasta la fecha evaluada, en los que registraste al menos una marcacion. |
| **Puntualidad** | Porcentaje y cantidad de dias considerados puntuales en el periodo. |
| **Marcaciones incompletas** | Dias que requieren revisar una entrada o salida. |
| **Tardanza al ingresar** | Minutos acumulados y dias con tardanza. |
| **Salida anticipada** | Minutos acumulados y dias con salida antes del horario esperado. |
| **Incidencias de horario** | Total de minutos de tardanza y salida anticipada. |
| **Sin marcacion** | Dias programados sin una marcacion registrada. |
| **Comparacion** | Variacion frente al periodo anterior indicado por la aplicacion. |

### 6.2 Ver el detalle diario

Puedes tocar las tarjetas de **Dias marcados**, **Puntualidad**, **Marcaciones incompletas**, **Tardanza al ingresar**, **Salida anticipada** o **Sin marcacion** para abrir el detalle correspondiente.

En el detalle se muestra, segun la informacion disponible:

- Fecha.
- Horario esperado de entrada y salida.
- Primera y ultima marcacion.
- Cantidad de marcaciones.
- Estado del dia.
- Minutos de tardanza o salida anticipada.

Cuando exista una sola marcacion, el detalle puede indicar que parece una entrada o una salida y que falta confirmar la otra marca. Esta indicacion es informativa.

**[Insertar captura 9: detalle diario de asistencia]**

### 6.3 Estados de asistencia

| Estado | Significado |
| --- | --- |
| **Puntual** | No se registraron incidencias de horario para ese dia. |
| **Tarde** | Se registraron minutos de tardanza al ingresar. |
| **Salida anticipada** | Se registro salida antes del horario esperado. |
| **Tarde y salida anticipada** | Se registraron ambas incidencias. |
| **Marcacion incompleta** | Falta una entrada o salida por confirmar. |
| **Sin marcacion** | Dia programado sin registros. |
| **Dia libre** | Dia no programado para asistencia. |

---

## 7. Perfil y cierre de sesion

En **Perfil** puedes revisar el nombre y correo de la cuenta con la que ingresaste.

Para cerrar sesion:

1. Pulsa **Perfil**.
2. Pulsa **Cerrar sesion**.
3. Espera el retorno a la pantalla de inicio de sesion.

Tambien puedes usar el icono de salida disponible en la pantalla de Registro.

**[Insertar captura 10: pantalla Perfil]**

---

## 8. Problemas frecuentes

| Situacion | Que hacer |
| --- | --- |
| El boton de marcacion esta deshabilitado. | Revisa que la hora este sincronizada. Si se solicita ubicacion, activa el GPS, concede el permiso y espera el estado **Dentro del perimetro**. |
| Aparece "Fuera del perimetro". | Acercate al lugar autorizado y actualiza tu ubicacion. |
| Aparece "Sin sincronizacion con servidor". | Verifica Internet, espera unos segundos y vuelve a intentarlo. |
| No puedo iniciar sesion. | Usa tu cuenta institucional y verifica Internet. Si el problema continua, comunicate con soporte. |
| Se indica que no tengo DNI asociado. | Solicita al administrador que asocie tu DNI a tu cuenta institucional. |
| Se indica que la cuenta esta asociada a otro dispositivo. | Comunicate con soporte para revisar la autorizacion del dispositivo. |
| No aparece informacion en el Panel. | Selecciona otro mes o vuelve a intentarlo cuando tengas conexion. Puede no haber datos para el periodo elegido. |
| Veo un codigo junto a un error. | Anota el codigo, la fecha y hora del intento, y comunicate con soporte. |

Al solicitar soporte, incluye:

- Tu correo institucional.
- Fecha y hora aproximada del problema.
- Captura de pantalla del mensaje.
- Codigo de error mostrado por la aplicacion, si existe.

---

## 9. Recomendaciones de uso

- Registra tu asistencia personalmente.
- Mantén habilitada la conexion a Internet durante el registro.
- No cambies manualmente la hora del dispositivo.
- Revisa la confirmacion antes de retirarte del lugar de marcacion.
- Consulta el Panel de forma periodica para identificar marcaciones incompletas o incidencias.
- Cierra sesion si usas un dispositivo compartido.

---

## 10. Control de cambios del documento

| Version del manual | Fecha | Cambio realizado |
| --- | --- | --- |
| 1.0 | [Completar] | Primera version del manual de usuario. |
