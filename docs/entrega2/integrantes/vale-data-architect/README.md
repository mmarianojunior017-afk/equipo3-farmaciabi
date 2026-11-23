# Vale · Data Architect / SQL Specialist

Equipo 3 · Proyecto Integrador · Entrega 2 · FarmaciaBI. Sección **11** del script integrado.

## Aportación

- Auditoría de nombres fuera del estándar (20 columnas con mayúsculas antes de refactorizar).
- Refactorización con `sp_rename`: 6 tablas y 20 columnas al estándar `dim_` / `fact_` / `stg_`, `id_`, `fch_`, `mto_`.
- Diseño de la tabla de auditoría `aud_linaje_carga` (11 columnas, sin llaves foráneas).
- Recreación de `vw_ventas_operativas` (Vista 1), `sp_insertar_paciente` (SP1) y `sp_consultar_paciente_por_id` (SP2) con los nombres nuevos.
- Propiedades extendidas (`MS_Description`) de `dim_pacientes` y `dim_medicamentos`: 11 descripciones (2 de tabla y 9 de columna).

## Resultado

Las 30 columnas de las 6 tablas originales quedan en minúsculas; la vista operativa regresa 5 filas; `PAC-101` regresa 1 fila con "sin correo registrado".

## Contenido de esta carpeta

- [`sql/seccion_11_nomenclatura_y_dimensiones.sql`](sql/seccion_11_nomenclatura_y_dimensiones.sql): código de la sección 11, tomado de [`sql/Equipo03_Entrega2.sql`](../../Equipo03_Entrega2.sql).
- `evidencias/`: capturas de ejecución en SQL Server (las mismas del PDF de la entrega).

- [`11-1_antes_nombres_fuera_de_estandar.png`](evidencias/11-1_antes_nombres_fuera_de_estandar.png)
- [`11-2_despues_refactorizacion_1de2.png`](evidencias/11-2_despues_refactorizacion_1de2.png)
- [`11-2_despues_refactorizacion_2de2.png`](evidencias/11-2_despues_refactorizacion_2de2.png)
- [`11-5_vw_ventas_operativas_1de2.png`](evidencias/11-5_vw_ventas_operativas_1de2.png)
- [`11-5_vw_ventas_operativas_2de2.png`](evidencias/11-5_vw_ventas_operativas_2de2.png)
- [`11-8_propiedades_extendidas_dimensiones.png`](evidencias/11-8_propiedades_extendidas_dimensiones.png)
- [`11-9_vista_y_sp_consultar_paciente.png`](evidencias/11-9_vista_y_sp_consultar_paciente.png)

## Cómo ejecutarlo

Este archivo no corre solo: depende de las tablas y objetos que crean las secciones anteriores. Para reproducir todo, ejecuta completo (F5) [`sql/Equipo03_Entrega2.sql`](../../Equipo03_Entrega2.sql); el script borra y vuelve a crear FarmaciaBI. Cierra antes cualquier otra pestaña conectada a esa base.
