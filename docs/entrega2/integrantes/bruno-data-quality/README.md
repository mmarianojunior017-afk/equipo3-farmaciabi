# Bruno · Data Quality & QA Specialist

Equipo 3 · Proyecto Integrador · Entrega 2 · FarmaciaBI. Sección **14** del script integrado.

## Aportación

- Procedimiento `sp_ObtenerDiccionarioDatos` (Opción B de la actividad) y su ejecución para las 7 tablas.
- Validaciones de calidad: 0 columnas sin descripción, las 7 tablas con descripción a nivel tabla, 0 nombres fuera de estándar (antes 20).
- Cuadre de vistas y procedimientos contra las tablas después del cambio de nombres.
- Respuestas a las preguntas de la Clase 17 (C17.1 a C17.5).
- Hallazgo: en un SQL Server en español, `'2026-08-01'` se leía como 8 de enero y el historial salía vacío; el script usa el formato `yyyymmdd`.

## Resultado

41 columnas documentadas en 7 tablas; Vista 360: 5 filas y $2,820; KPI: 3 filas y 4 quejas; historial de PAC-101: 2 filas.

## Contenido de esta carpeta

- [`sql/seccion_14_diccionario_y_calidad.sql`](sql/seccion_14_diccionario_y_calidad.sql): código de la sección 14, tomado de [`sql/Equipo03_Entrega2.sql`](../../Equipo03_Entrega2.sql).
- `evidencias/`: capturas de ejecución en SQL Server (las mismas del PDF de la entrega).

- [`14-10_descripcion_a_nivel_tabla.png`](evidencias/14-10_descripcion_a_nivel_tabla.png)
- [`14-11_nombres_fuera_de_estandar.png`](evidencias/14-11_nombres_fuera_de_estandar.png)
- [`14-12_cuadre_de_vistas_y_sp.png`](evidencias/14-12_cuadre_de_vistas_y_sp.png)
- [`14-1_creacion_sp_ObtenerDiccionarioDatos.png`](evidencias/14-1_creacion_sp_ObtenerDiccionarioDatos.png)
- [`14-2_diccionario_dim_pacientes.png`](evidencias/14-2_diccionario_dim_pacientes.png)
- [`14-3_diccionario_dim_medicamentos.png`](evidencias/14-3_diccionario_dim_medicamentos.png)
- [`14-4_diccionario_fact_ventas_farmacia.png`](evidencias/14-4_diccionario_fact_ventas_farmacia.png)
- [`14-5_diccionario_fact_tickets_atencion.png`](evidencias/14-5_diccionario_fact_tickets_atencion.png)
- [`14-6_diccionario_stg_medicamentos.png`](evidencias/14-6_diccionario_stg_medicamentos.png)
- [`14-7_diccionario_stg_tickets.png`](evidencias/14-7_diccionario_stg_tickets.png)
- [`14-8_diccionario_aud_linaje_carga.png`](evidencias/14-8_diccionario_aud_linaje_carga.png)
- [`14-9_columnas_sin_descripcion.png`](evidencias/14-9_columnas_sin_descripcion.png)
- [`C17-1_dato_crudo_vs_metadato.png`](evidencias/C17-1_dato_crudo_vs_metadato.png)
- [`C17-2_columnas_fch_y_mto.png`](evidencias/C17-2_columnas_fch_y_mto.png)
- [`C17-4_llaves_foraneas.png`](evidencias/C17-4_llaves_foraneas.png)

## Cómo ejecutarlo

Este archivo no corre solo: depende de las tablas y objetos que crean las secciones anteriores. Para reproducir todo, ejecuta completo (F5) [`sql/Equipo03_Entrega2.sql`](../../Equipo03_Entrega2.sql); el script borra y vuelve a crear FarmaciaBI. Cierra antes cualquier otra pestaña conectada a esa base.
