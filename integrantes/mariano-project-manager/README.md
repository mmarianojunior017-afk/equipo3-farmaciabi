# Mariano · Project Manager / Communicator

Equipo 3 · Proyecto Integrador · Entrega 2 · FarmaciaBI. Sección **15** del script integrado.

## Aportación

- Rastreo del linaje del ingreso de $2,820 de la Vista 360 (5 pasos, 2 fuentes).
- Estado final de la documentación: 7 tablas y 41 columnas documentadas.
- Integración del script único del equipo, el PDF, la presentación y este repositorio.
- Reflexión: por qué el linaje importa en auditorías de cumplimiento.

## Resultado

Los montos y pacientes vienen de la BD operacional de ventas; el medicamento, del catálogo COFEPRIS (JSON). 7 tablas y 41 columnas documentadas.

## Contenido de esta carpeta

- [`sql/seccion_15_linaje_y_cierre.sql`](sql/seccion_15_linaje_y_cierre.sql): código de la sección 15, tomado de [`sql/Equipo03_Entrega2.sql`](../../sql/Equipo03_Entrega2.sql).
- `evidencias/`: capturas de ejecución en SQL Server (las mismas del PDF de la entrega).

- [`15-1_linaje_del_ingreso_2820.png`](evidencias/15-1_linaje_del_ingreso_2820.png)
- [`15-2_estado_final_documentacion.png`](evidencias/15-2_estado_final_documentacion.png)

## Cómo ejecutarlo

Este archivo no corre solo: depende de las tablas y objetos que crean las secciones anteriores. Para reproducir todo, ejecuta completo (F5) [`sql/Equipo03_Entrega2.sql`](../../sql/Equipo03_Entrega2.sql); el script borra y vuelve a crear FarmaciaBI. Cierra antes cualquier otra pestaña conectada a esa base.
