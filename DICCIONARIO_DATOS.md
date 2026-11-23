# Diccionario de datos · FarmaciaBI

Base de datos **FarmaciaBI** (SQL Server) · Equipo 3 · Integración de Datos, Otoño 2026 · Universidad Iberoamericana León.

Resumen: **8 tablas y 47 columnas** en los esquemas `bronce` y `plata`, todas con descripción de negocio registrada con `sys.sp_addextendedproperty` (`MS_Description`) en [`src/01_ddl_arquitectura_der.sql`](src/01_ddl_arquitectura_der.sql). Las descripciones de este archivo salen de ese mismo script. El esquema `oro` contiene vistas. En SQL Server el diccionario de una tabla se obtiene con `exec dbo.sp_ObtenerDiccionarioDatos @NombreTabla = 'plata.dim_pacientes';`.

## Estándar de nomenclatura (Clase 17)

- Minúsculas y `snake_case`.
- Esquemas: `bronce`, `plata`, `oro`.
- Prefijos: `stg_` (bronce), `dim_` (dimensiones), `fact_` (hechos), `aud_` (auditoría), `vw_` (vistas), `sp_` (procedimientos).
- Abreviaturas: `id_` (identificador), `fch_` (fecha), `mto_` (monto).

## Relaciones (esquema plata)

| Tabla hija | Columna FK | Tabla padre | Cardinalidad |
|---|---|---|---|
| plata.fact_ventas_farmacia | id_paciente | plata.dim_pacientes | N:1 |
| plata.fact_ventas_farmacia | ean_medicamento | plata.dim_medicamentos | N:1 |
| plata.fact_tickets_atencion | id_venta | plata.fact_ventas_farmacia | N:1 |

Las tablas de bronce y `plata.aud_linaje_carga` no tienen llaves foráneas por diseño. DER: [`assets/diagrama_der_sqlserver.png`](assets/diagrama_der_sqlserver.png).

## bronce.stg_medicamentos
**Capa bronce** · Responsable: Daniel

Tabla de la capa bronce que recibe el catálogo de medicamentos de COFEPRIS (JSON) tal como llega, sin restricciones, para diagnosticarlo antes de limpiarlo y cargarlo a plata.dim_medicamentos.

| Columna | Tipo | Permite nulos | Llave / regla | Descripción de negocio |
|---|---|---|---|---|
| `ean_medicamento` | varchar(50) | Sí |  | Código EAN recibido como texto desde la fuente, antes de validar que tenga 13 caracteres. |
| `nombre_comercial` | varchar(150) | Sí |  | Nombre comercial del medicamento tal como viene en el JSON de COFEPRIS. |
| `sustancia_activa` | varchar(150) | Sí |  | Sustancia activa del medicamento tal como viene en el JSON de COFEPRIS. |
| `requiere_receta` | varchar(20) | Sí |  | Indicador de receta médica recibido de la fuente; se estandariza a SI / NO en mayúsculas antes de la carga final. |
| `estatus_alerta_sanitaria` | varchar(100) | Sí |  | Estatus de alerta sanitaria reportado por la fuente, pendiente de validación. |

## bronce.stg_tickets
**Capa bronce** · Responsable: Daniel

Tabla de la capa bronce que recibe los tickets de atención desde el archivo CSV sin restricciones, para diagnosticar nulos, espacios y variantes de escritura antes de cargarlos a plata.fact_tickets_atencion.

| Columna | Tipo | Permite nulos | Llave / regla | Descripción de negocio |
|---|---|---|---|---|
| `id_ticket` | varchar(20) | Sí |  | Identificador del ticket tal como viene en el archivo CSV. |
| `id_venta` | varchar(20) | Sí |  | Identificador de la venta asociada al ticket, aún sin validar contra fact_ventas_farmacia. |
| `motivo_atencion` | varchar(150) | Sí |  | Motivo de atención tal como viene en el archivo CSV. |
| `estatus_ticket` | varchar(100) | Sí |  | Estatus del ticket con las variantes de la fuente (espacios, mayúsculas, sin acento); se homologa a Cerrado / En Escalación. |
| `tiempo_resolucion_min` | int | Sí |  | Tiempo de resolución en minutos tal como viene en el CSV; puede llegar nulo y se imputa con el promedio. |

## bronce.stg_ventas
**Capa bronce** · Responsable: Daniel

Tabla de la capa bronce que recibe las ventas de la base operacional (SQL) tal como llegan, todo como texto, para diagnosticarlas y convertirlas con try_convert antes de cargarlas a plata.fact_ventas_farmacia.

| Columna | Tipo | Permite nulos | Llave / regla | Descripción de negocio |
|---|---|---|---|---|
| `id_venta` | varchar(20) | Sí |  | Identificador de la venta tal como viene de la base operacional. |
| `fch_venta` | varchar(30) | Sí |  | Fecha y hora de la venta como texto en formato yyyymmdd hh:mm:ss; se convierte con try_convert al cargar a plata. |
| `id_paciente` | varchar(20) | Sí |  | Identificador del cliente (paciente) tal como viene en la venta; de aquí se generan los registros de plata.dim_pacientes. |
| `ean_medicamento` | varchar(50) | Sí |  | Código EAN del medicamento vendido, recibido como texto. |
| `cantidad_piezas` | varchar(20) | Sí |  | Número de piezas recibido como texto; se convierte a entero y debe ser mayor a cero. |
| `monto_total_mxn` | varchar(30) | Sí |  | Importe total en pesos recibido como texto; se convierte a decimal y debe ser mayor a cero. |

## plata.dim_pacientes
**Capa plata · dimensión** · Responsable: Vale

Dimensión maestra de pacientes de la farmacia. Centraliza la identidad de cada paciente para la Vista 360 y para los procedimientos de alta, consulta e historial de compras.

| Columna | Tipo | Permite nulos | Llave / regla | Descripción de negocio |
|---|---|---|---|---|
| `id_paciente` | varchar(10) | No | PK | Identificador único del paciente con formato PAC-###, tomado del ID de cliente de la base operacional de ventas. |
| `nombre` | varchar(100) | No |  | Nombre(s) del paciente. Se guarda sin espacios al inicio ni al final para evitar duplicados visuales. |
| `apellido` | varchar(100) | No |  | Apellido(s) del paciente. Se guarda sin espacios al inicio ni al final. |
| `correo` | varchar(150) | Sí |  | Correo electrónico de contacto del paciente, en minúsculas. Es opcional; cuando falta, los reportes muestran "sin correo registrado". |

## plata.dim_medicamentos
**Capa plata · dimensión** · Responsable: Vale

Dimensión maestra del catálogo de medicamentos, homologado desde la fuente COFEPRIS (JSON). Define la clasificación regulatoria y el estatus sanitario de cada producto.

| Columna | Tipo | Permite nulos | Llave / regla | Descripción de negocio |
|---|---|---|---|---|
| `ean_medicamento` | varchar(13) | No | PK | Código de barras EAN-13 del medicamento. Se guarda como texto de 13 caracteres para no perder ceros a la izquierda y es la llave para cruzar ventas con el catálogo. |
| `nombre_comercial` | varchar(150) | No |  | Nombre comercial o de marca con su presentación (ej. Tempra Forte 650mg); es el nombre que ve el cliente en mostrador. |
| `sustancia_activa` | varchar(150) | No |  | Principio activo del medicamento. Agrupa productos equivalentes y es el eje de los indicadores de vw_kpi_sustancia_activa. |
| `requiere_receta` | varchar(2) | No | CHECK SI / NO | Indicador regulatorio de venta: SI = requiere receta médica, NO = venta libre. Permite medir el cumplimiento normativo del ingreso. |
| `estatus_alerta_sanitaria` | varchar(50) | Sí |  | Estatus sanitario del producto según COFEPRIS (ej. Vigente, Bajo Revisión). Permite identificar ventas de productos con alerta. |

## plata.fact_ventas_farmacia
**Capa plata · hechos** · Responsable: Max

Tabla de hechos de ventas. Registra cada transacción del punto de venta y vincula al paciente con el medicamento, la cantidad y el importe cobrado.

| Columna | Tipo | Permite nulos | Llave / regla | Descripción de negocio |
|---|---|---|---|---|
| `id_venta` | varchar(10) | No | PK | Identificador único de la venta con formato FAR-###. |
| `fch_venta` | datetime | No |  | Fecha y hora en que se registró la venta. Se usa para los historiales por rango de fechas. |
| `id_paciente` | varchar(10) | No | FK → plata.dim_pacientes | Paciente que realizó la compra. Llave foránea hacia dim_pacientes. |
| `ean_medicamento` | varchar(13) | No | FK → plata.dim_medicamentos | Medicamento vendido. Llave foránea hacia dim_medicamentos. |
| `cantidad_piezas` | int | No | CHECK > 0 | Número de piezas vendidas en la transacción. Regla de negocio: debe ser mayor a cero. |
| `mto_total_mxn` | decimal(10,2) | No | CHECK > 0 | Importe total cobrado en pesos mexicanos (MXN). Regla de negocio: debe ser mayor a cero; es la base del ingreso en todos los KPI. |

## plata.fact_tickets_atencion
**Capa plata · hechos** · Responsable: Max

Tabla de hechos de atención al cliente. Registra las quejas e incidencias que se originan en una venta y su tiempo de resolución.

| Columna | Tipo | Permite nulos | Llave / regla | Descripción de negocio |
|---|---|---|---|---|
| `id_ticket` | varchar(10) | No | PK | Identificador único del ticket de atención con formato TCK-###. |
| `id_venta` | varchar(10) | No | FK → plata.fact_ventas_farmacia | Venta que originó el ticket. Llave foránea hacia fact_ventas_farmacia; liga la queja con el paciente y el medicamento. |
| `motivo_atencion` | varchar(100) | No |  | Motivo de la incidencia reportada (ej. Cobro Incorrecto, Surtido Incompleto, Efecto Secundario Reportado, Duda de Posología). |
| `estatus_ticket` | varchar(50) | No | CHECK Cerrado / En Escalación | Estatus estandarizado del ticket en el flujo de atención: Cerrado o En Escalación. |
| `tiempo_resolucion_min` | int | Sí |  | Minutos que tomó resolver el ticket. Los valores faltantes se imputaron con el promedio de los tickets con tiempo registrado. |

## plata.aud_linaje_carga
**Capa plata · auditoría** · Responsable: Vale (diseño) y Daniel (carga)

Bitácora de auditoría del pipeline ETL. Registra cada paso de ingesta, transformación y carga con su fuente, tabla destino, regla aplicada y conteo de registros para dar trazabilidad (linaje) a cada cifra.

| Columna | Tipo | Permite nulos | Llave / regla | Descripción de negocio |
|---|---|---|---|---|
| `id_carga` | int identity | No | PK | Identificador autoincremental del paso de carga registrado en la bitácora. |
| `fase_pipeline` | varchar(20) | No |  | Fase del pipeline en la que ocurrió el paso: Ingesta (fuente a bronce) o Plata (bronce a plata). |
| `nombre_fuente` | varchar(100) | No |  | Fuente de negocio de donde provienen los datos (catálogo COFEPRIS, tickets de atención o base operacional de ventas). |
| `tipo_fuente` | varchar(10) | No |  | Formato técnico de la fuente: JSON, CSV o SQL. |
| `tabla_origen` | varchar(128) | Sí |  | Tabla de la que se leyeron los datos. Es nula cuando el origen es un archivo o sistema externo. |
| `tabla_destino` | varchar(128) | No |  | Tabla, con su esquema, en la que quedaron los datos después del paso. |
| `regla_aplicada` | varchar(300) | No |  | Regla de negocio o de limpieza que se aplicó en el paso (ej. homologación de estatus, imputación con promedio). |
| `num_registros_origen` | int | No |  | Número de registros que entraron al paso; se compara con el destino para detectar pérdidas. |
| `num_registros_destino` | int | No |  | Número de registros que quedaron en la tabla destino al terminar el paso. |
| `fch_carga` | datetime2 | No |  | Fecha y hora en que se registró el paso en la bitácora (metadato operativo). |
| `responsable_carga` | varchar(50) | No |  | Integrante del equipo responsable del paso, para saber a quién consultar en una auditoría. |

## Esquema oro: vistas y procedimientos

| Objeto | Tipo | Responsable | Para qué sirve |
|---|---|---|---|
| oro.vw_ventas_operativas | Vista 1 | Vale | Ventas con paciente y medicamento, textos limpios y precio unitario |
| oro.vw_vista360_farmacia | Vista 360° | Max | Paciente + venta + medicamento + ticket (left join, conserva ventas sin queja) |
| oro.vw_kpi_sustancia_activa | Vista KPI | Max | Por sustancia activa: ventas, piezas, ingreso, ticket promedio, quejas y tiempo de resolución |
| oro.sp_historial_paciente | SP3 | Max | Historial de compras de un paciente por rango de fechas |
| plata.sp_ejecutar_pipeline | Orquestador | Daniel | Ejecuta la carga de bronce a plata (idempotente) y registra el linaje |
| plata.sp_cargar_dim_medicamentos, sp_cargar_dim_pacientes, sp_cargar_fact_ventas, sp_cargar_fact_tickets | Limpieza | Daniel | Limpian, deduplican, validan y cargan cada tabla de plata |
| plata.sp_registrar_linaje | Linaje | Daniel | Guarda el recorrido de cada fuente en `plata.aud_linaje_carga` |
| plata.sp_insertar_paciente, plata.sp_consultar_paciente_por_id | SP1 y SP2 | Vale | Alta controlada y consulta de pacientes |
| dbo.sp_ObtenerDiccionarioDatos | SP de clase | Bruno | Extrae el diccionario de una tabla desde `sys.columns` y `MS_Description` |
