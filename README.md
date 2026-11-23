# FarmaciaBI · Operaciones Farmacéuticas y Servicio (Vista 360°)
### Integración de Datos en SQL Server

**Materia:** Integración de Datos | Universidad Iberoamericana León
**Equipo:** 3 | **Tablero Trello:** [Equipo 3 · Proyecto Integrador · Farmacia](https://trello.com/b/3bMUF3YB/equipo-3-proyecto-integrador-farmacia)

![Logo del Negocio](assets/logo_negocio.png)

## 1. Descripción del Proyecto
FarmaciaBI simula la operación de una farmacia: ventas de medicamentos, el catálogo regulatorio de COFEPRIS y los tickets de atención al cliente. Se integran tres fuentes originales: la base operacional de ventas (SQL), el catálogo de medicamentos (JSON) y los tickets de atención (CSV). El objetivo analítico es una **Vista 360°** que responda preguntas de negocio: cumplimiento normativo (receta vs. venta libre), ventas de productos bajo alerta sanitaria, quejas por principio activo y eficiencia en soporte. Todo se implementa en **Microsoft SQL Server** con una arquitectura de capas Bronce → Plata → Oro.

## 2. Arquitectura de Integración (SQL Server)
![Flujo de Integración Medallón](assets/flujo_medallon_sql.png)

* **Capa bronce (ingesta):** `stg_medicamentos` y `stg_tickets` reciben las fuentes crudas, sin restricciones, para diagnosticarlas antes de limpiarlas.
* **Capa plata (transformación y QA):** estandarización de textos (`ltrim`/`rtrim`/`lower`/`upper`), deduplicación con `row_number`, imputación de nulos con `coalesce`, carga a `dim_pacientes`, `dim_medicamentos`, `fact_ventas_farmacia` y `fact_tickets_atencion` con llaves primarias y foráneas, validaciones de calidad y la bitácora de linaje `aud_linaje_carga`.
* **Capa oro (consumo y BI):** `vw_ventas_operativas`, `vw_vista360_farmacia` (Vista 360°) y `vw_kpi_sustancia_activa` (KPIs por sustancia activa).

Estándar de nombres (Clase 17): minúsculas y `snake_case`; prefijos `stg_`, `dim_`, `fact_`, `aud_`, `vw_`, `sp_`; abreviaturas `id_`, `fch_` y `mto_`.

## 3. Modelo Entidad-Relación (DER)
![Diagrama Entidad-Relación](assets/diagrama_der_sqlserver.png)

7 tablas y 3 llaves foráneas (`fact_ventas_farmacia` → `dim_pacientes`, `fact_ventas_farmacia` → `dim_medicamentos`, `fact_tickets_atencion` → `fact_ventas_farmacia`). Detalle de columnas y tipos en [`DICCIONARIO_DATOS.md`](DICCIONARIO_DATOS.md).

## 4. Estructura del Repositorio (`/src`)
* `01_ddl_arquitectura_der.sql`: creación de la base de datos y de las tablas relacionales (PK, FK y tipos de dato).
* `02_etl_ingesta_bronce.sql`: carga inicial a staging (`INSERT`) y diagnóstico de los datos crudos.
* `03_etl_limpieza_plata.sql`: estandarización, deduplicación, imputación, carga a tablas finales y reglas de calidad.
* `04_vistas_gold_bi.sql`: vistas finales, procedimientos almacenados, preguntas de negocio y KPIs, además de la refactorización de nombres, el diccionario de datos y el linaje.

Se ejecutan en orden **01 → 02 → 03 → 04** en SQL Server Management Studio. El script `01` borra y vuelve a crear la base `FarmaciaBI`; cierra antes cualquier otra pestaña conectada a ella. Los cuatro archivos juntos equivalen a [`docs/entrega2/Equipo03_Entrega2.sql`](docs/entrega2/Equipo03_Entrega2.sql), el script integrado de la Entrega 2.

Documentación de la Entrega 2 (evidencias por integrante y PDF): [`docs/entrega2`](docs/entrega2).

## 5. Integrantes y Roles (4 Roles Oficiales)
* **Data Architect / SQL Specialist:** Vale
* **Data Engineer / Pipeline Lead:** Daniel
* **Data Quality & QA Specialist:** Bruno
* **Líder de Proyecto:** Mariano Muñoz Canchola
* **BI & Analytics Specialist:** Max (Maximiliano)

*(Equipo de 5: el rol 4 se divide en Líder de Proyecto y BI Specialist.)*
