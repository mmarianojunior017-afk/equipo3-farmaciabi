# Diccionario de datos · FarmaciaBI

Base de datos **FarmaciaBI** (SQL Server) · Equipo 3 · Integración de Datos, Otoño 2026 · Universidad Iberoamericana León.

Resumen: **7 tablas y 41 columnas**, todas con descripción de negocio registrada con `sys.sp_addextendedproperty` (`MS_Description`). Las descripciones de este archivo se tomaron del propio script `sql/Equipo03_Entrega2.sql`; el mismo contenido se obtiene en SQL Server con `exec sp_ObtenerDiccionarioDatos @NombreTabla = '<tabla>'`.

## Estándar de nomenclatura (Clase 17)

- Minúsculas y `snake_case`.
- Prefijos: `dim_` (maestras), `fact_` (transaccionales), `stg_` (staging), `aud_` (auditoría), `vw_` (vistas), `sp_` (procedimientos).
- Abreviaturas: `id_` (identificador), `fch_` (fecha), `mto_` (monto).

## Relaciones

| Tabla hija | Columna FK | Tabla padre | Cardinalidad |
|---|---|---|---|
| fact_ventas_farmacia | id_paciente | dim_pacientes | N:1 |
| fact_ventas_farmacia | ean_medicamento | dim_medicamentos | N:1 |
| fact_tickets_atencion | id_venta | fact_ventas_farmacia | N:1 |

Las tablas `stg_` y `aud_linaje_carga` no tienen llaves foráneas por diseño. DER: [`modelo/FarmaciaBI_DER_Entrega2.png`](modelo/FarmaciaBI_DER_Entrega2.png).

## dim_pacientes
**Dimensión maestra** · Responsable: Vale

Dimensión maestra de pacientes de la farmacia. Centraliza la identidad de cada paciente para la Vista 360 y para los procedimientos de alta, consulta e historial de compras.

| Columna | Tipo | Permite nulos | Llave | Descripción de negocio |
|---|---|---|---|---|
| `id_paciente` | varchar(10) | No | PK | Identificador único del paciente con formato PAC-###, tomado del ID de cliente de la base operacional de ventas. |
| `nombre` | varchar(100) | No |  | Nombre(s) del paciente. Se guarda sin espacios al inicio ni al final para evitar duplicados visuales. |
| `apellido` | varchar(100) | No |  | Apellido(s) del paciente. Se guarda sin espacios al inicio ni al final. |
| `correo` | varchar(150) | Sí |  | Correo electrónico de contacto del paciente, en minúsculas. Es opcional; cuando falta, los reportes muestran "sin correo registrado". |

## dim_medicamentos
**Dimensión maestra** · Responsable: Vale

Dimensión maestra del catálogo de medicamentos, homologado desde la fuente COFEPRIS (JSON). Define la clasificación regulatoria y el estatus sanitario de cada producto.

| Columna | Tipo | Permite nulos | Llave | Descripción de negocio |
|---|---|---|---|---|
| `ean_medicamento` | varchar(13) | No | PK | Código de barras EAN-13 del medicamento. Se guarda como texto de 13 caracteres para no perder ceros a la izquierda y es la llave para cruzar ventas con el catálogo. |
| `nombre_comercial` | varchar(150) | No |  | Nombre comercial o de marca con su presentación (ej. Tempra Forte 650mg); es el nombre que ve el cliente en mostrador. |
| `sustancia_activa` | varchar(150) | No |  | Principio activo del medicamento. Agrupa productos equivalentes y es el eje de los indicadores de vw_kpi_sustancia_activa. |
| `requiere_receta` | varchar(2) | No |  | Indicador regulatorio de venta: SI = requiere receta médica, NO = venta libre. Permite medir el cumplimiento normativo del ingreso. |
| `estatus_alerta_sanitaria` | varchar(50) | Sí |  | Estatus sanitario del producto según COFEPRIS (ej. Vigente, Bajo Revisión). Permite identificar ventas de productos con alerta. |

## fact_ventas_farmacia
**Tabla de hechos** · Responsable: Max

Tabla de hechos de ventas. Registra cada transacción del punto de venta y vincula al paciente con el medicamento, la cantidad y el importe cobrado.

| Columna | Tipo | Permite nulos | Llave | Descripción de negocio |
|---|---|---|---|---|
| `id_venta` | varchar(10) | No | PK | Identificador único de la venta con formato FAR-###. |
| `fch_venta` | datetime | No |  | Fecha y hora en que se registró la venta. Se usa para los historiales por rango de fechas. |
| `id_paciente` | varchar(10) | No | FK → dim_pacientes | Paciente que realizó la compra. Llave foránea hacia dim_pacientes. |
| `ean_medicamento` | varchar(13) | No | FK → dim_medicamentos | Medicamento vendido. Llave foránea hacia dim_medicamentos. |
| `cantidad_piezas` | int | No |  | Número de piezas vendidas en la transacción. Regla de negocio: debe ser mayor a cero. |
| `mto_total_mxn` | decimal(10,2) | No |  | Importe total cobrado en pesos mexicanos (MXN). Regla de negocio: debe ser mayor a cero; es la base del ingreso en todos los KPI. |

## fact_tickets_atencion
**Tabla de hechos** · Responsable: Max

Tabla de hechos de atención al cliente. Registra las quejas e incidencias que se originan en una venta y su tiempo de resolución.

| Columna | Tipo | Permite nulos | Llave | Descripción de negocio |
|---|---|---|---|---|
| `id_ticket` | varchar(10) | No | PK | Identificador único del ticket de atención con formato TCK-###. |
| `id_venta` | varchar(10) | No | FK → fact_ventas_farmacia | Venta que originó el ticket. Llave foránea hacia fact_ventas_farmacia; liga la queja con el paciente y el medicamento. |
| `motivo_atencion` | varchar(100) | No |  | Motivo de la incidencia reportada (ej. Cobro Incorrecto, Surtido Incompleto, Efecto Secundario Reportado, Duda de Posología). |
| `estatus_ticket` | varchar(50) | No |  | Estatus estandarizado del ticket en el flujo de atención: Cerrado o En Escalación. |
| `tiempo_resolucion_min` | int | Sí |  | Minutos que tomó resolver el ticket. Los valores faltantes se imputaron con el promedio de los tickets con tiempo registrado. |

## stg_medicamentos
**Staging** · Responsable: Daniel

Tabla de staging que recibe el catálogo de medicamentos de COFEPRIS (JSON) tal como llega, sin restricciones, para diagnosticarlo y limpiarlo antes de cargarlo a dim_medicamentos.

| Columna | Tipo | Permite nulos | Llave | Descripción de negocio |
|---|---|---|---|---|
| `ean_medicamento` | varchar(50) | Sí |  | Código EAN recibido como texto desde la fuente, antes de validar que tenga 13 caracteres. |
| `nombre_comercial` | varchar(150) | Sí |  | Nombre comercial del medicamento tal como viene en el JSON de COFEPRIS. |
| `sustancia_activa` | varchar(150) | Sí |  | Sustancia activa del medicamento tal como viene en el JSON de COFEPRIS. |
| `requiere_receta` | varchar(20) | Sí |  | Indicador de receta médica recibido de la fuente; se estandariza a SI / NO en mayúsculas antes de la carga final. |
| `estatus_alerta_sanitaria` | varchar(100) | Sí |  | Estatus de alerta sanitaria reportado por la fuente, pendiente de validación. |

## stg_tickets
**Staging** · Responsable: Daniel

Tabla de staging que recibe los tickets de atención desde el archivo CSV sin restricciones, para diagnosticar nulos, espacios y variantes de escritura antes de cargarlos a fact_tickets_atencion.

| Columna | Tipo | Permite nulos | Llave | Descripción de negocio |
|---|---|---|---|---|
| `id_ticket` | varchar(20) | Sí |  | Identificador del ticket tal como viene en el archivo CSV. |
| `id_venta` | varchar(20) | Sí |  | Identificador de la venta asociada al ticket, aún sin validar contra fact_ventas_farmacia. |
| `motivo_atencion` | varchar(150) | Sí |  | Motivo de atención tal como viene en el archivo CSV. |
| `estatus_ticket` | varchar(100) | Sí |  | Estatus del ticket con las variantes de la fuente (espacios, mayúsculas, sin acento); se homologa a Cerrado / En Escalación. |
| `tiempo_resolucion_min` | int | Sí |  | Tiempo de resolución en minutos tal como viene en el CSV; puede llegar nulo y se imputa con el promedio. |

## aud_linaje_carga
**Auditoría / linaje** · Responsable: Vale (diseño) y Daniel (carga)

Bitácora de auditoría del pipeline ETL. Registra cada paso de ingesta, transformación y carga con su fuente, tabla destino, regla aplicada y conteo de registros para dar trazabilidad (linaje) a cada cifra.

| Columna | Tipo | Permite nulos | Llave | Descripción de negocio |
|---|---|---|---|---|
| `id_carga` | int identity | No | PK | Identificador autoincremental del paso de carga registrado en la bitácora. |
| `fase_pipeline` | varchar(20) | No |  | Fase del pipeline en la que ocurrió el paso: Ingesta, Transformacion o Carga. |
| `nombre_fuente` | varchar(100) | No |  | Fuente de negocio de donde provienen los datos (catálogo COFEPRIS, tickets de atención o base operacional de ventas). |
| `tipo_fuente` | varchar(10) | No |  | Formato técnico de la fuente: JSON, CSV o SQL. |
| `tabla_origen` | varchar(128) | Sí |  | Tabla de la que se leyeron los datos. Es nula cuando el origen es un archivo o sistema externo. |
| `tabla_destino` | varchar(128) | No |  | Tabla de FarmaciaBI en la que quedaron los datos después del paso. |
| `regla_aplicada` | varchar(300) | No |  | Regla de negocio o de limpieza que se aplicó en el paso (ej. homologación de estatus, imputación con promedio). |
| `num_registros_origen` | int | No |  | Número de registros que entraron al paso; se compara con el destino para detectar pérdidas. |
| `num_registros_destino` | int | No |  | Número de registros que quedaron en la tabla destino al terminar el paso. |
| `fch_carga` | datetime2 | No |  | Fecha y hora en que se registró el paso en la bitácora (metadato operativo). |
| `responsable_carga` | varchar(50) | No |  | Integrante del equipo responsable del paso, para saber a quién consultar en una auditoría. |

## Vistas y procedimientos

| Objeto | Tipo | Responsable | Para qué sirve |
|---|---|---|---|
| vw_ventas_operativas | Vista 1 | Vale | Ventas con paciente y medicamento, textos limpios y precio unitario |
| vw_vista360_farmacia | Vista 2 | Max | Vista 360: paciente + venta + medicamento + ticket (left join, conserva ventas sin queja) |
| vw_kpi_sustancia_activa | Vista 3 | Max | KPI por sustancia activa: ventas, piezas, ingreso, ticket promedio, quejas, tiempo de resolución |
| sp_insertar_paciente | SP1 | Vale | Alta controlada de paciente (limpia espacios, correo en minúsculas, rechaza IDs repetidos) |
| sp_consultar_paciente_por_id | SP2 | Vale | Consulta de paciente por ID; correo por defecto "sin correo registrado" |
| sp_historial_paciente | SP3 | Max | Historial de compras de un paciente por rango de fechas |
| sp_ObtenerDiccionarioDatos | SP de clase | Bruno | Extrae el diccionario de una tabla desde `sys.columns` y `MS_Description` |
