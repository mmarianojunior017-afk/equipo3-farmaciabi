# FarmaciaBI · Equipo 3

Proyecto Integrador de **Integración de Datos** (Otoño 2026) · Universidad Iberoamericana León · Docente: Julio César Moreno Ramón.

Modelo de datos de **Operaciones Farmacéuticas y Servicio (Vista 360°)** en SQL Server. Integra tres fuentes: la base operacional de ventas (SQL), el catálogo de medicamentos de COFEPRIS (JSON) y los tickets de atención (CSV), con limpieza en staging, vistas analíticas, diccionario de datos y linaje.

## Equipo

| Integrante | Rol | Sección (Entrega 2) | Carpeta |
|---|---|---|---|
| Mariano | Project Manager / Communicator | 15 · Linaje y cierre | [`integrantes/mariano-project-manager`](integrantes/mariano-project-manager) |
| Vale | Data Architect / SQL Specialist | 11 · Nomenclatura y dimensiones | [`integrantes/vale-data-architect`](integrantes/vale-data-architect) |
| Daniel | Data Engineer / Pipeline Lead | 12 · Linaje y staging | [`integrantes/daniel-data-engineer`](integrantes/daniel-data-engineer) |
| Bruno | Data Quality & QA Specialist | 14 · Diccionario y calidad | [`integrantes/bruno-data-quality`](integrantes/bruno-data-quality) |
| Max | BI & Analytics Specialist | 13 · Hechos y capa semántica | [`integrantes/max-bi-analytics`](integrantes/max-bi-analytics) |

## Estructura del repositorio

```
.
├── README.md
├── DICCIONARIO_DATOS.md                 ← diccionario de las 7 tablas y 41 columnas
├── sql/
│   ├── Equipo03_Entrega2.sql            ← script integrado (corre completo con F5)
│   └── 00_avance1_modelo_y_limpieza.sql ← Avance 1 (secciones 0 a 10)
├── modelo/
│   └── FarmaciaBI_DER_Entrega2.png      ← DER (dbdiagram.io)
├── entregas/
│   └── entrega2/                        ← PDF de la Entrega 2
└── integrantes/
    ├── mariano-project-manager/         ← README, sql/, evidencias/
    ├── vale-data-architect/
    ├── daniel-data-engineer/
    ├── bruno-data-quality/
    └── max-bi-analytics/
```

Cada carpeta de integrante tiene su `README.md`, el código de su sección en `sql/` y las capturas de su trabajo en `evidencias/`.

## Cómo reproducir

1. Abre `sql/Equipo03_Entrega2.sql` en SSMS (o VS Code con la extensión MSSQL), conectado a una instancia de SQL Server.
2. Cierra cualquier otra pestaña conectada a `FarmaciaBI`: el script borra y vuelve a crear la base.
3. Ejecuta el script completo (F5). Crea el modelo, carga los datos de ejemplo, limpia, refactoriza los nombres, documenta con `MS_Description` y registra el linaje.
4. Para ver el diccionario de una tabla: `exec sp_ObtenerDiccionarioDatos @NombreTabla = 'dim_pacientes';`

Las fechas del script usan el formato `yyyymmdd` para que SQL Server las interprete igual en cualquier idioma.

## Modelo

| Capa | Objetos |
|---|---|
| Dimensiones | `dim_pacientes`, `dim_medicamentos` |
| Hechos | `fact_ventas_farmacia`, `fact_tickets_atencion` |
| Staging | `stg_medicamentos`, `stg_tickets` |
| Auditoría | `aud_linaje_carga` |
| Vistas | `vw_ventas_operativas`, `vw_vista360_farmacia`, `vw_kpi_sustancia_activa` |
| Procedimientos | `sp_insertar_paciente`, `sp_consultar_paciente_por_id`, `sp_historial_paciente`, `sp_ObtenerDiccionarioDatos` |

Estándar de nomenclatura (Clase 17): minúsculas y `snake_case`; prefijos `dim_`, `fact_`, `stg_`, `aud_`; abreviaturas `id_`, `fch_`, `mto_`. Detalle en [`DICCIONARIO_DATOS.md`](DICCIONARIO_DATOS.md).

## Entregas

| Entrega | Contenido | Ubicación |
|---|---|---|
| Avance 1 | Modelo, staging, limpieza, vistas, procedimientos y preguntas de negocio | [`sql/00_avance1_modelo_y_limpieza.sql`](sql/00_avance1_modelo_y_limpieza.sql) |
| Entrega 2 | Metadatos, diccionario de datos y linaje | [`entregas/entrega2`](entregas/entrega2) |
