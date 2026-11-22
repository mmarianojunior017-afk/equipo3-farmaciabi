# Daniel · Data Engineer / Pipeline Lead

Equipo 3 · Proyecto Integrador · Entrega 2 · FarmaciaBI. Sección **12** del script integrado.

## Aportación

- Registro del linaje del pipeline en `aud_linaje_carga`: 8 pasos (2 de Ingesta, 2 de Transformación y 4 de Carga). Los conteos se calculan con `count(*)` sobre las tablas reales.
- Verificación de que no se perdió ningún registro: diferencia 0 entre origen y destino en los 8 pasos.
- Propiedades extendidas de `stg_medicamentos`, `stg_tickets` y `aud_linaje_carga`: 24 descripciones.

## Resultado

8 pasos registrados, 0 con diferencias; 24 descripciones registradas.

## Contenido de esta carpeta

- [`sql/seccion_12_linaje_y_staging.sql`](sql/seccion_12_linaje_y_staging.sql): código de la sección 12, tomado de [`sql/Equipo03_Entrega2.sql`](../../sql/Equipo03_Entrega2.sql).
- `evidencias/`: capturas de ejecución en SQL Server (las mismas del PDF de la entrega).

- [`12-1_aud_linaje_carga_tramo1.png`](evidencias/12-1_aud_linaje_carga_tramo1.png)
- [`12-1_aud_linaje_carga_tramo2.png`](evidencias/12-1_aud_linaje_carga_tramo2.png)
- [`12-1_aud_linaje_carga_tramo3.png`](evidencias/12-1_aud_linaje_carga_tramo3.png)
- [`12-2_recorrido_y_diferencias.png`](evidencias/12-2_recorrido_y_diferencias.png)
- [`12-2_verificacion_pasos_sin_diferencias.png`](evidencias/12-2_verificacion_pasos_sin_diferencias.png)
- [`12-3_descripciones_filas_1_a_20.png`](evidencias/12-3_descripciones_filas_1_a_20.png)
- [`12-3_descripciones_filas_21_a_24.png`](evidencias/12-3_descripciones_filas_21_a_24.png)

## Cómo ejecutarlo

Este archivo no corre solo: depende de las tablas y objetos que crean las secciones anteriores. Para reproducir todo, ejecuta completo (F5) [`sql/Equipo03_Entrega2.sql`](../../sql/Equipo03_Entrega2.sql); el script borra y vuelve a crear FarmaciaBI. Cierra antes cualquier otra pestaña conectada a esa base.
