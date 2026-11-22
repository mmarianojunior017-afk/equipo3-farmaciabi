# Max (Maximiliano) · BI & Analytics Specialist

Equipo 3 · Proyecto Integrador · Entrega 2 · FarmaciaBI. Sección **13** del script integrado.

## Aportación

- Capa semántica de la Clase 17: `vw_vista360_farmacia` (Vista 2) y `vw_kpi_sustancia_activa` (Vista 3) con nombres estandarizados.
- `sp_historial_paciente` (SP3): historial de compras por paciente y rango de fechas.
- Propiedades extendidas de `fact_ventas_farmacia` y `fact_tickets_atencion`: 13 descripciones (2 de tabla y 11 de columna).
- Comprobación de que la refactorización no cambió ninguna cifra de negocio (receta $1,350 = 47.87 %, venta libre $1,470 = 52.13 %).

## Resultado

Vista 360: 5 ventas (FAR-904 sin ticket); KPI: 3 sustancias activas, $2,820 y 4 quejas; historial de PAC-101 en agosto: FAR-901 ($180) y FAR-904 ($90).

## Contenido de esta carpeta

- [`sql/seccion_13_hechos_y_capa_semantica.sql`](sql/seccion_13_hechos_y_capa_semantica.sql): código de la sección 13, tomado de [`sql/Equipo03_Entrega2.sql`](../../sql/Equipo03_Entrega2.sql).
- `evidencias/`: capturas de ejecución en SQL Server (las mismas del PDF de la entrega).

- [`13-1_vw_vista360_columnas_ticket.png`](evidencias/13-1_vw_vista360_columnas_ticket.png)
- [`13-1_vw_vista360_columnas_venta.png`](evidencias/13-1_vw_vista360_columnas_venta.png)
- [`13-2_vw_kpi_sustancia_activa.png`](evidencias/13-2_vw_kpi_sustancia_activa.png)
- [`13-3_sp_historial_paciente.png`](evidencias/13-3_sp_historial_paciente.png)
- [`13-4_descripciones_tablas_de_hechos.png`](evidencias/13-4_descripciones_tablas_de_hechos.png)
- [`13-5_cifras_de_negocio_sin_cambio.png`](evidencias/13-5_cifras_de_negocio_sin_cambio.png)

## Cómo ejecutarlo

Este archivo no corre solo: depende de las tablas y objetos que crean las secciones anteriores. Para reproducir todo, ejecuta completo (F5) [`sql/Equipo03_Entrega2.sql`](../../sql/Equipo03_Entrega2.sql); el script borra y vuelve a crear FarmaciaBI. Cierra antes cualquier otra pestaña conectada a esa base.
