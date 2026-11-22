/**
14. DICCIONARIO DE DATOS Y CALIDAD - BRUNO (Data Quality & QA Specialist)
Opcion B de la actividad: procedimiento sp_ObtenerDiccionarioDatos (nombre dado por el profesor) ejecutado
para las 7 tablas. Despues se valida que la documentacion este completa y se responden las preguntas de la Clase 17.
**/
if object_id('sp_ObtenerDiccionarioDatos', 'P') is not null
    drop procedure sp_ObtenerDiccionarioDatos;
go


/**
14.1 Procedimiento de clase para extraer el diccionario de una tabla
**/
create procedure sp_ObtenerDiccionarioDatos
    @NombreTabla varchar(128)
as
begin
    set nocount on;

    if not exists (select 1 from sys.tables where name = @NombreTabla)
    begin
        raiserror('La tabla especificada no existe en la base de datos.', 16, 1);
        return;
    end;

    select
        t.name as [Tabla],
        c.name as [Columna],
        tp.name as [Tipo de Dato],
        c.max_length as [Longitud Máxima],
        case when c.is_nullable = 1 then 'Sí' else 'No' end as [Permite Nulos],
        isnull(cast(ep.value as varchar(500)), 'Sin documentación técnica') as [Descripción de Negocio]
    from sys.tables t
    inner join sys.columns c
        on t.object_id = c.object_id
    inner join sys.types tp
        on c.user_type_id = tp.user_type_id
    left join sys.extended_properties ep
        on ep.major_id = t.object_id
        and ep.minor_id = c.column_id
        and ep.name = N'MS_Description'
    where t.name = @NombreTabla
    order by c.column_id;
end;
go


/**
Pregunta 14.2: Cual es el diccionario de datos de la dimension maestra dim_pacientes?
R= 4 columnas, todas con descripcion de negocio; solo correo permite nulos.
**/
exec sp_ObtenerDiccionarioDatos @NombreTabla = 'dim_pacientes';


/**
Pregunta 14.3: Cual es el diccionario de datos de la dimension maestra dim_medicamentos?
R= 5 columnas, todas con descripcion de negocio; solo estatus_alerta_sanitaria permite nulos.
**/
exec sp_ObtenerDiccionarioDatos @NombreTabla = 'dim_medicamentos';


/**
Pregunta 14.4: Cual es el diccionario de datos de la tabla de hechos fact_ventas_farmacia?
R= 6 columnas, todas con descripcion de negocio; ninguna permite nulos.
**/
exec sp_ObtenerDiccionarioDatos @NombreTabla = 'fact_ventas_farmacia';


/**
Pregunta 14.5: Cual es el diccionario de datos de la tabla de hechos fact_tickets_atencion?
R= 5 columnas, todas con descripcion de negocio; solo tiempo_resolucion_min permite nulos.
**/
exec sp_ObtenerDiccionarioDatos @NombreTabla = 'fact_tickets_atencion';


/**
Pregunta 14.6: Cual es el diccionario de datos de la tabla staging stg_medicamentos?
R= 5 columnas, todas con descripcion de negocio; todas permiten nulos (staging sin restricciones).
**/
exec sp_ObtenerDiccionarioDatos @NombreTabla = 'stg_medicamentos';


/**
Pregunta 14.7: Cual es el diccionario de datos de la tabla staging stg_tickets?
R= 5 columnas, todas con descripcion de negocio; todas permiten nulos (staging sin restricciones).
**/
exec sp_ObtenerDiccionarioDatos @NombreTabla = 'stg_tickets';


/**
Pregunta 14.8: Cual es el diccionario de datos de la tabla de auditoria aud_linaje_carga?
R= 11 columnas, todas con descripcion de negocio; solo tabla_origen permite nulos.
**/
exec sp_ObtenerDiccionarioDatos @NombreTabla = 'aud_linaje_carga';


/**
Pregunta 14.9: Queda alguna columna de la base sin descripcion de negocio?
R= 0 registros. Las 41 columnas de las 7 tablas quedaron documentadas.
**/
select
    t.name as tabla,
    c.name as columna
from sys.tables t
inner join sys.columns c
    on t.object_id = c.object_id
left join sys.extended_properties ep
    on ep.major_id = t.object_id
    and ep.minor_id = c.column_id
    and ep.name = N'MS_Description'
where ep.value is null;


/**
Pregunta 14.10: Todas las tablas tienen descripcion a nivel tabla?
minor_id = 0 es la propiedad de la tabla; minor_id > 0 es la de una columna.
R= Si. Las 7 tablas regresan su descripcion; ninguna dice "Sin documentación".
**/
select
    t.name as tabla,
    isnull(cast(ep.value as varchar(500)), 'Sin documentación') as descripcion_tabla
from sys.tables t
left join sys.extended_properties ep
    on ep.major_id = t.object_id
    and ep.minor_id = 0
    and ep.name = N'MS_Description'
order by t.name;


/**
Pregunta 14.11: Despues de la refactorizacion de Vale, queda algun nombre fuera del estandar?
Es la misma consulta de la pregunta 11.1 (antes daba 20 registros).
R= 0 registros. Las 7 tablas y sus 41 columnas estan en minusculas.
**/
select
    t.name as tabla,
    c.name as columna
from sys.tables t
inner join sys.columns c
    on t.object_id = c.object_id
where t.name collate Latin1_General_CS_AS <> lower(t.name)
    or c.name collate Latin1_General_CS_AS <> lower(c.name);


/**
Pregunta 14.12: Las vistas y procedimientos siguen cuadrando contra las tablas despues del cambio de nombres?
R= Vista 360: 5 filas y $2,820. Vista KPI: 3 filas y 4 quejas. Historial de PAC-101 en agosto: 2 filas (FAR-901 y FAR-904).
**/
select
    count(*) as filas_vista360,
    sum(mto_total_mxn) as mto_ingreso_vista360
from vw_vista360_farmacia;

select
    count(*) as filas_kpi,
    sum(num_quejas) as quejas_kpi
from vw_kpi_sustancia_activa;

exec sp_historial_paciente 'PAC-101', '2026-08-01', '2026-08-31';


/**
PREGUNTAS DE LA CLASE 17 APLICADAS A FARMACIABI

Pregunta C17.1 (Comprobacion de conceptos 1): Cual es la diferencia principal entre un dato crudo y un metadato?
R= El dato crudo es el valor que guarda la tabla: 'PAC-101' o 180.00 en fact_ventas_farmacia. El metadato es la
informacion que describe ese valor: que mto_total_mxn es decimal(10,2), que no acepta nulos y que significa el importe
cobrado en pesos. La primera consulta regresa datos; sp_ObtenerDiccionarioDatos (14.2 a 14.8) regresa metadatos.
**/
select top 3
    id_venta,
    id_paciente,
    mto_total_mxn
from fact_ventas_farmacia
order by id_venta;


/**
Pregunta C17.2 (Comprobacion de conceptos 2): Por que mezclar camelCase y snake_case dificulta la automatizacion?
R= Porque un script automatico localiza columnas por patron. Con el estandar, todas las fechas empiezan con fch_ y todos
los montos con mto_, y una sola consulta las encuentra: 3 columnas (fch_venta, mto_total_mxn y fch_carga).
En el Avance 1 la misma busqueda no encontraba Fecha_Hora ni Monto_Total_MXN, y habria que escribir cada caso a mano.
**/
select
    t.name as tabla,
    c.name as columna,
    tp.name as tipo_dato
from sys.tables t
inner join sys.columns c
    on t.object_id = c.object_id
inner join sys.types tp
    on c.user_type_id = tp.user_type_id
where c.name like 'fch[_]%'
    or c.name like 'mto[_]%'
order by
    t.name,
    c.name;


/**
Pregunta C17.3 (Micro-caso): Un Data Warehouse llama a la fecha de registro de 5 formas distintas. Que impacto tiene y como se resuelve con vistas?
R= Impacto: JOINs erroneos, consultas duplicadas y dashboards con cifras distintas para el mismo concepto.
Solucion: una capa de vistas de abstraccion que renombra las columnas antes de exponerlas a BI. En FarmaciaBI esa capa
son vw_ventas_operativas, vw_vista360_farmacia y vw_kpi_sustancia_activa: Power BI solo ve fch_venta y mto_total_mxn,
aunque una fuente futura traiga "fecha_reg" o "date_created".

Pregunta C17.4 (Quiz de cierre), respuestas:
1. La fecha de carga es un metadato operativo (en el proyecto vive en aud_linaje_carga.fch_carga).
2. El caso recomendado para SQL es snake_case en minusculas.
3. La PK y la FK se vinculan con la restriccion foreign key (integridad referencial). La siguiente consulta muestra las 3 del proyecto.
4. El diccionario se guarda en DICCIONARIO_DATOS.md, en la raiz del repositorio Git.
5. Homogeneizar prefijos previene ambiguedad y errores de mayusculas/minusculas, y deja ver el tipo de objeto por su nombre (dim_, fact_, stg_, vw_, sp_).
R= 3 llaves foraneas: fact_ventas_farmacia.id_paciente -> dim_pacientes, fact_ventas_farmacia.ean_medicamento -> dim_medicamentos
y fact_tickets_atencion.id_venta -> fact_ventas_farmacia.
**/
select
    object_name(fkc.parent_object_id) as tabla_hija,
    col_name(fkc.parent_object_id, fkc.parent_column_id) as columna_fk,
    object_name(fkc.referenced_object_id) as tabla_padre,
    col_name(fkc.referenced_object_id, fkc.referenced_column_id) as columna_pk
from sys.foreign_key_columns fkc
order by tabla_hija;


/**
Pregunta C17.5: Donde vive cada tipo de metadato de la Clase 17 (lamina 5) en FarmaciaBI?
R= Tecnicos (tipo, longitud, nulidad): sys.columns y sys.types, columnas 3 a 5 del diccionario.
De negocio (definicion): MS_Description, ultima columna del diccionario.
Operativos (fecha de carga, origen, linaje): aud_linaje_carga, la tabla nueva de Daniel.
**/
