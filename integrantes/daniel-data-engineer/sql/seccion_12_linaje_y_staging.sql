/**
12. LINAJE Y STAGING - DANIEL (Data Engineer / Pipeline Lead)
Se registra en aud_linaje_carga el recorrido que hicieron los datos en el Avance 1:
Ingesta (fuente -> staging), Transformacion (limpieza en staging) y Carga (staging o fuente -> tablas finales).
Los conteos se calculan con count(*) sobre las tablas reales, no se escriben a mano.
**/

/**
12.1 Registro del linaje del pipeline
**/
insert into aud_linaje_carga (
    fase_pipeline,
    nombre_fuente,
    tipo_fuente,
    tabla_origen,
    tabla_destino,
    regla_aplicada,
    num_registros_origen,
    num_registros_destino,
    fch_carga,
    responsable_carga
)
select 'Ingesta', 'Catálogo COFEPRIS', 'JSON', null, 'stg_medicamentos',
    'Carga sin restricciones; el EAN se recibe como texto para no perder ceros a la izquierda',
    3, (select count(*) from stg_medicamentos), getdate(), 'Daniel'
union all
select 'Ingesta', 'Tickets de atención', 'CSV', null, 'stg_tickets',
    'Carga sin restricciones para poder diagnosticar nulos, espacios y variantes de escritura',
    4, (select count(*) from stg_tickets), getdate(), 'Daniel'
union all
select 'Transformacion', 'Catálogo COFEPRIS', 'JSON', 'stg_medicamentos', 'stg_medicamentos',
    'ltrim/rtrim en textos, upper en requiere_receta y deduplicacion por EAN con row_number',
    (select count(*) from stg_medicamentos), (select count(*) from stg_medicamentos), getdate(), 'Daniel'
union all
select 'Transformacion', 'Tickets de atención', 'CSV', 'stg_tickets', 'stg_tickets',
    'Homologacion de estatus (Cerrado / En Escalación), deduplicacion con row_number e imputacion del tiempo nulo con el promedio',
    (select count(*) from stg_tickets), (select count(*) from stg_tickets), getdate(), 'Daniel'
union all
select 'Carga', 'Catálogo COFEPRIS', 'JSON', 'stg_medicamentos', 'dim_medicamentos',
    'cast del EAN a varchar(13) y carga al catalogo maestro',
    (select count(*) from stg_medicamentos), (select count(*) from dim_medicamentos), getdate(), 'Daniel'
union all
select 'Carga', 'BD operacional de ventas', 'SQL', null, 'dim_pacientes',
    'Alta de pacientes a partir del ID de cliente de las ventas (supuesto del equipo)',
    4, (select count(*) from dim_pacientes), getdate(), 'Daniel'
union all
select 'Carga', 'BD operacional de ventas', 'SQL', null, 'fact_ventas_farmacia',
    'Validacion de cantidades y montos mayores a cero y fechas dentro de agosto 2026',
    5, (select count(*) from fact_ventas_farmacia), getdate(), 'Daniel'
union all
select 'Carga', 'Tickets de atención', 'CSV', 'stg_tickets', 'fact_tickets_atencion',
    'Integridad referencial: cada ticket debe apuntar a una venta existente en fact_ventas_farmacia',
    (select count(*) from stg_tickets), (select count(*) from fact_tickets_atencion), getdate(), 'Daniel';


/**
Pregunta 12.2: Que recorrido siguieron los datos y se perdio algun registro en el camino?
R= 8 pasos: 2 de Ingesta, 2 de Transformacion y 4 de Carga. En los 8 coinciden origen y destino
(3 medicamentos, 4 tickets, 4 pacientes, 5 ventas): no se perdio ningun registro.
**/
select
    id_carga,
    fase_pipeline,
    nombre_fuente,
    tipo_fuente,
    coalesce(tabla_origen, 'archivo / sistema externo') as tabla_origen,
    tabla_destino,
    num_registros_origen,
    num_registros_destino,
    num_registros_origen - num_registros_destino as diferencia
from aud_linaje_carga
order by id_carga;


/**
12.3 Propiedades extendidas de staging y de la bitacora (stg_medicamentos, stg_tickets, aud_linaje_carga)
**/
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tabla de staging que recibe el catálogo de medicamentos de COFEPRIS (JSON) tal como llega, sin restricciones, para diagnosticarlo y limpiarlo antes de cargarlo a dim_medicamentos.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'stg_medicamentos';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Código EAN recibido como texto desde la fuente, antes de validar que tenga 13 caracteres.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'stg_medicamentos',
    @level2type = N'COLUMN', @level2name = N'ean_medicamento';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Nombre comercial del medicamento tal como viene en el JSON de COFEPRIS.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'stg_medicamentos',
    @level2type = N'COLUMN', @level2name = N'nombre_comercial';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Sustancia activa del medicamento tal como viene en el JSON de COFEPRIS.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'stg_medicamentos',
    @level2type = N'COLUMN', @level2name = N'sustancia_activa';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Indicador de receta médica recibido de la fuente; se estandariza a SI / NO en mayúsculas antes de la carga final.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'stg_medicamentos',
    @level2type = N'COLUMN', @level2name = N'requiere_receta';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Estatus de alerta sanitaria reportado por la fuente, pendiente de validación.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'stg_medicamentos',
    @level2type = N'COLUMN', @level2name = N'estatus_alerta_sanitaria';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tabla de staging que recibe los tickets de atención desde el archivo CSV sin restricciones, para diagnosticar nulos, espacios y variantes de escritura antes de cargarlos a fact_tickets_atencion.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'stg_tickets';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador del ticket tal como viene en el archivo CSV.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'stg_tickets',
    @level2type = N'COLUMN', @level2name = N'id_ticket';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador de la venta asociada al ticket, aún sin validar contra fact_ventas_farmacia.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'stg_tickets',
    @level2type = N'COLUMN', @level2name = N'id_venta';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Motivo de atención tal como viene en el archivo CSV.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'stg_tickets',
    @level2type = N'COLUMN', @level2name = N'motivo_atencion';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Estatus del ticket con las variantes de la fuente (espacios, mayúsculas, sin acento); se homologa a Cerrado / En Escalación.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'stg_tickets',
    @level2type = N'COLUMN', @level2name = N'estatus_ticket';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tiempo de resolución en minutos tal como viene en el CSV; puede llegar nulo y se imputa con el promedio.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'stg_tickets',
    @level2type = N'COLUMN', @level2name = N'tiempo_resolucion_min';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Bitácora de auditoría del pipeline ETL. Registra cada paso de ingesta, transformación y carga con su fuente, tabla destino, regla aplicada y conteo de registros para dar trazabilidad (linaje) a cada cifra.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador autoincremental del paso de carga registrado en la bitácora.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'id_carga';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Fase del pipeline en la que ocurrió el paso: Ingesta, Transformacion o Carga.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'fase_pipeline';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Fuente de negocio de donde provienen los datos (catálogo COFEPRIS, tickets de atención o base operacional de ventas).',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'nombre_fuente';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Formato técnico de la fuente: JSON, CSV o SQL.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'tipo_fuente';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tabla de la que se leyeron los datos. Es nula cuando el origen es un archivo o sistema externo.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'tabla_origen';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tabla de FarmaciaBI en la que quedaron los datos después del paso.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'tabla_destino';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Regla de negocio o de limpieza que se aplicó en el paso (ej. homologación de estatus, imputación con promedio).',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'regla_aplicada';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Número de registros que entraron al paso; se compara con el destino para detectar pérdidas.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'num_registros_origen';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Número de registros que quedaron en la tabla destino al terminar el paso.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'num_registros_destino';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Fecha y hora en que se registró el paso en la bitácora (metadato operativo).',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'fch_carga';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Integrante del equipo responsable del paso, para saber a quién consultar en una auditoría.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'responsable_carga';
go
