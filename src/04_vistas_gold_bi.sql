/**
EQUIPO 3 - FarmaciaBI | Integracion de Datos | Universidad Iberoamericana Leon
04_vistas_gold_bi.sql
Capa oro: Vista 360, KPIs, procedimientos de consumo, diccionario y linaje

Vistas del esquema oro que consumen BI (Power BI / Excel), procedimiento de historial, pruebas, preguntas de negocio,
el procedimiento sp_ObtenerDiccionarioDatos (nombre indicado por el profesor) y la validacion de la documentacion.
Necesita que ya se hayan ejecutado 01, 02 y 03.

Roles: Vale (Vista 1), Max (Vista 360, KPIs, historial y preguntas de negocio) y Bruno (diccionario y pruebas).

Orden de ejecucion: 01 -> 02 -> 03 -> 04 (SQL Server 2019, SSMS). Cada archivo puede ejecutarse completo con F5.
**/
use FarmaciaBI;
go


/**
10. VISTAS DE LA CAPA ORO
10.1 Vista 1 (Operativa) - VALE
Consolida cada venta con su paciente y su medicamento, con textos limpios y precio unitario.
**/
create or alter view oro.vw_ventas_operativas as
select
    v.id_venta,
    v.fch_venta,
    v.id_paciente,
    ltrim(rtrim(p.nombre)) as nombre,
    ltrim(rtrim(p.apellido)) as apellido,
    v.ean_medicamento,
    ltrim(rtrim(m.nombre_comercial)) as medicamento,
    ltrim(rtrim(m.sustancia_activa)) as sustancia_activa,
    m.requiere_receta,
    m.estatus_alerta_sanitaria,
    v.cantidad_piezas,
    v.mto_total_mxn,
    cast(v.mto_total_mxn / nullif(v.cantidad_piezas, 0) as decimal(10,2)) as mto_precio_unitario
from plata.fact_ventas_farmacia v
inner join plata.dim_pacientes p
    on v.id_paciente = p.id_paciente
inner join plata.dim_medicamentos m
    on v.ean_medicamento = m.ean_medicamento;
go


/**
10.2 Vista 2 (Analitica 360) - MAX
Une en una fila al paciente, la venta, el medicamento y la queja. El left join hacia fact_tickets_atencion
conserva las ventas sin queja (FAR-904) con los campos del ticket en null.
**/
create or alter view oro.vw_vista360_farmacia as
select
    p.id_paciente,
    ltrim(rtrim(p.nombre)) + ' ' + ltrim(rtrim(p.apellido)) as nombre_paciente,
    v.id_venta,
    v.fch_venta,
    v.ean_medicamento,
    m.nombre_comercial,
    m.sustancia_activa,
    m.requiere_receta,
    m.estatus_alerta_sanitaria,
    v.cantidad_piezas,
    v.mto_total_mxn,
    t.id_ticket,
    t.motivo_atencion,
    t.estatus_ticket,
    t.tiempo_resolucion_min
from plata.dim_pacientes p
inner join plata.fact_ventas_farmacia v
    on p.id_paciente = v.id_paciente
inner join plata.dim_medicamentos m
    on v.ean_medicamento = m.ean_medicamento
left join plata.fact_tickets_atencion t
    on v.id_venta = t.id_venta;
go


/**
10.3 Vista 3 (Resumen KPI) - MAX
Resumen ejecutivo por sustancia activa: ventas, piezas, ingreso, ticket promedio, quejas y tiempo promedio de resolucion.
**/
create or alter view oro.vw_kpi_sustancia_activa as
select
    sustancia_activa,
    requiere_receta,
    estatus_alerta_sanitaria,
    count(id_venta) as num_ventas,
    sum(cantidad_piezas) as piezas_vendidas,
    sum(mto_total_mxn) as mto_ingreso_total_mxn,
    avg(mto_total_mxn) as mto_ticket_promedio_mxn,
    count(id_ticket) as num_quejas,
    avg(tiempo_resolucion_min * 1.0) as tiempo_promedio_resolucion_min
from oro.vw_vista360_farmacia
group by
    sustancia_activa,
    requiere_receta,
    estatus_alerta_sanitaria;
go


/**
10.4 SP3 - Historial de compras de un paciente por rango de fechas - MAX
Cruza la dimension con la tabla de hechos (inner join) y devuelve las compras en orden cronologico.
**/
create or alter procedure oro.sp_historial_paciente
    @id_paciente varchar(10),
    @fch_inicio date,
    @fch_fin date
as
begin
    set nocount on;

    select
        p.id_paciente,
        ltrim(rtrim(p.nombre)) + ' ' + ltrim(rtrim(p.apellido)) as nombre_paciente,
        v.id_venta,
        v.fch_venta,
        m.nombre_comercial,
        m.sustancia_activa,
        v.cantidad_piezas,
        v.mto_total_mxn
    from plata.dim_pacientes p
    inner join plata.fact_ventas_farmacia v
        on p.id_paciente = v.id_paciente
    inner join plata.dim_medicamentos m
        on v.ean_medicamento = m.ean_medicamento
    where p.id_paciente = @id_paciente
        and cast(v.fch_venta as date) between @fch_inicio and @fch_fin
    order by v.fch_venta;
end;
go


/**
11. PRUEBAS DE VISTAS Y PROCEDIMIENTOS - BRUNO
Pregunta 11.1: Cuadran las vistas contra las tablas de plata?
R= Vista 1: 5 filas. Vista 360: 5 filas y $2,820, con FAR-904 sin ticket. Vista KPI: 3 filas, $2,820 y 4 quejas.
**/
select
    count(*) as filas_vista_operativa
from oro.vw_ventas_operativas;

select
    count(*) as filas_vista360,
    sum(mto_total_mxn) as mto_ingreso_vista360
from oro.vw_vista360_farmacia;

select
    id_venta,
    id_ticket
from oro.vw_vista360_farmacia
where id_ticket is null;

select
    count(*) as filas_kpi,
    sum(mto_ingreso_total_mxn) as mto_ingreso_kpi,
    sum(num_quejas) as quejas_kpi
from oro.vw_kpi_sustancia_activa;


/**
Pregunta 11.2: sp_insertar_paciente limpia los datos y rechaza IDs repetidos?
Se inserta un paciente con espacios y mayusculas, se inserta otra vez y se borra.
R= Se guarda [PAC-105], [Juan], [Perez], [juan.perez@gmail.com]. La segunda ejecucion manda
el mensaje "El paciente ya existe en la base de datos." (resultado esperado).
**/
exec plata.sp_insertar_paciente '  PAC-105 ', '  Juan ', ' Perez  ', ' JUAN.PEREZ@GMAIL.COM ';

exec plata.sp_insertar_paciente 'PAC-105', 'Juan', 'Perez', null;

select
    '[' + id_paciente + ']' as ID_Visible,
    '[' + nombre + ']' as Nombre_Visible,
    '[' + apellido + ']' as Apellido_Visible,
    '[' + correo + ']' as Correo_Visible
from plata.dim_pacientes
where id_paciente = 'PAC-105';

delete from plata.dim_pacientes
where id_paciente = 'PAC-105';


/**
Pregunta 11.3: sp_consultar_paciente_por_id regresa un paciente existente y uno inexistente?
R= PAC-101 regresa 1 fila con correo = "sin correo registrado". PAC-999 regresa 0 filas.
**/
exec plata.sp_consultar_paciente_por_id 'PAC-101';

exec plata.sp_consultar_paciente_por_id 'PAC-999';


/**
Pregunta 11.4: sp_historial_paciente regresa las compras de PAC-101 en agosto y en septiembre 2026?
R= Agosto regresa 2 filas (FAR-901 y FAR-904). Septiembre regresa 0 filas.
**/
exec oro.sp_historial_paciente 'PAC-101', '20260801', '20260831';

exec oro.sp_historial_paciente 'PAC-101', '20260901', '20260930';


/**
12. PREGUNTAS DE NEGOCIO E INSIGHTS DE LA CAPA ORO - MAX
Pregunta 1 - Cumplimiento normativo: que porcentaje del ingreso proviene de medicamentos con receta contra venta libre?
R= Con receta (Amoxil) $1,350 = 47.87%. Venta libre (Tempra y Bio-Grip) $1,470 = 52.13%. Ingreso total $2,820.
**/
select
    requiere_receta,
    sum(mto_total_mxn) as mto_ingreso_mxn,
    round(sum(mto_total_mxn) * 100.0 / (select sum(mto_total_mxn) from plata.fact_ventas_farmacia), 2) as porcentaje_ingreso
from oro.vw_vista360_farmacia
group by requiere_receta;


/**
Pregunta 2 - Alertas sanitarias: cual es el monto de venta acumulado de productos bajo revision o con alerta sanitaria?
R= Bio-Grip Restructurado (Bajo Revisión) acumula $1,200, el 42.55% del ingreso total.
**/
select
    nombre_comercial,
    estatus_alerta_sanitaria,
    sum(mto_total_mxn) as mto_acumulado_mxn
from oro.vw_vista360_farmacia
where estatus_alerta_sanitaria <> 'Vigente'
group by
    nombre_comercial,
    estatus_alerta_sanitaria;


/**
Pregunta 3 - Quejas por principio activo: que sustancias generan mas tickets por efecto secundario o surtido incompleto?
R= Empatan con 1 ticket cada una: Amoxicilina (Surtido Incompleto) y Antihistamínico Compuesto (Efecto Secundario Reportado).
**/
select
    sustancia_activa,
    motivo_atencion,
    count(id_ticket) as num_tickets
from oro.vw_vista360_farmacia
where motivo_atencion in ('Efecto Secundario Reportado', 'Surtido Incompleto')
group by
    sustancia_activa,
    motivo_atencion
order by num_tickets desc;


/**
Pregunta 4 - Eficiencia en soporte: cual es el tiempo promedio de resolucion tras imputar y como varia por tipo de queja?
R= Promedio general 16.50 min. Surtido Incompleto 25, Efecto Secundario Reportado 16 (imputado),
Cobro Incorrecto 15 y Duda de Posología 10.
**/
select
    motivo_atencion,
    count(id_ticket) as num_tickets,
    avg(tiempo_resolucion_min * 1.0) as tiempo_promedio_min
from plata.fact_tickets_atencion
group by motivo_atencion
order by tiempo_promedio_min desc;

select
    avg(tiempo_resolucion_min * 1.0) as tiempo_promedio_general_min
from plata.fact_tickets_atencion;


/**
Pregunta 5 - Linaje: de donde sale el ingreso de $2,820 de la Vista 360 y que reglas paso en el camino?
R= 5 pasos de 2 fuentes. Los montos y los pacientes vienen de la BD operacional de ventas (bronce.stg_ventas, 5 ventas validadas
y 4 pacientes); el medicamento viene del catalogo COFEPRIS en JSON (ingesta, limpieza y carga a plata.dim_medicamentos).
**/
select
    fase_pipeline,
    nombre_fuente,
    tipo_fuente,
    coalesce(tabla_origen, 'archivo / sistema externo') as tabla_origen,
    tabla_destino,
    regla_aplicada,
    num_registros_destino,
    responsable_carga
from plata.aud_linaje_carga
where tabla_destino in ('bronce.stg_medicamentos', 'bronce.stg_ventas', 'plata.dim_medicamentos', 'plata.dim_pacientes', 'plata.fact_ventas_farmacia')
order by id_carga;


/**
13. DICCIONARIO DE DATOS - BRUNO
Procedimiento sp_ObtenerDiccionarioDatos (nombre dado por el profesor). Recibe el nombre de la tabla, con o sin esquema
(por ejemplo 'dim_pacientes' o 'plata.dim_pacientes'), y regresa sus columnas con tipo, longitud, nulidad y descripcion de negocio.
**/
create or alter procedure dbo.sp_ObtenerDiccionarioDatos
    @NombreTabla varchar(128)
as
begin
    set nocount on;

    if not exists (
        select 1
        from sys.tables t
        inner join sys.schemas s
            on t.schema_id = s.schema_id
        where t.name = @NombreTabla
            or s.name + '.' + t.name = @NombreTabla
    )
    begin
        raiserror('La tabla especificada no existe en la base de datos.', 16, 1);
        return;
    end;

    select
        s.name as [Esquema],
        t.name as [Tabla],
        c.name as [Columna],
        tp.name as [Tipo de Dato],
        c.max_length as [Longitud Máxima],
        case when c.is_nullable = 1 then 'Sí' else 'No' end as [Permite Nulos],
        isnull(cast(ep.value as varchar(500)), 'Sin documentación técnica') as [Descripción de Negocio]
    from sys.tables t
    inner join sys.schemas s
        on t.schema_id = s.schema_id
    inner join sys.columns c
        on t.object_id = c.object_id
    inner join sys.types tp
        on c.user_type_id = tp.user_type_id
    left join sys.extended_properties ep
        on ep.major_id = t.object_id
        and ep.minor_id = c.column_id
        and ep.class = 1
        and ep.name = N'MS_Description'
    where t.name = @NombreTabla
        or s.name + '.' + t.name = @NombreTabla
    order by c.column_id;
end;
go


/**
Pregunta 13.1: Cual es el diccionario de datos de cada tabla de la base?
R= bronce.stg_medicamentos 5 columnas, bronce.stg_tickets 5, bronce.stg_ventas 6, plata.dim_pacientes 4,
plata.dim_medicamentos 5, plata.fact_ventas_farmacia 6, plata.fact_tickets_atencion 5 y plata.aud_linaje_carga 11.
Todas con descripcion de negocio.
**/
exec dbo.sp_ObtenerDiccionarioDatos @NombreTabla = 'bronce.stg_medicamentos';

exec dbo.sp_ObtenerDiccionarioDatos @NombreTabla = 'bronce.stg_tickets';

exec dbo.sp_ObtenerDiccionarioDatos @NombreTabla = 'bronce.stg_ventas';

exec dbo.sp_ObtenerDiccionarioDatos @NombreTabla = 'plata.dim_pacientes';

exec dbo.sp_ObtenerDiccionarioDatos @NombreTabla = 'plata.dim_medicamentos';

exec dbo.sp_ObtenerDiccionarioDatos @NombreTabla = 'plata.fact_ventas_farmacia';

exec dbo.sp_ObtenerDiccionarioDatos @NombreTabla = 'plata.fact_tickets_atencion';

exec dbo.sp_ObtenerDiccionarioDatos @NombreTabla = 'plata.aud_linaje_carga';


/**
Pregunta 13.2: Queda alguna columna de la base sin descripcion de negocio?
R= 0 registros. Las 47 columnas de las 8 tablas quedaron documentadas.
**/
select
    s.name as esquema,
    t.name as tabla,
    c.name as columna
from sys.tables t
inner join sys.schemas s
    on t.schema_id = s.schema_id
inner join sys.columns c
    on t.object_id = c.object_id
left join sys.extended_properties ep
    on ep.major_id = t.object_id
    and ep.minor_id = c.column_id
    and ep.class = 1
    and ep.name = N'MS_Description'
where ep.value is null;


/**
Pregunta 13.3: Cual es el estado final de la documentacion del modelo?
R= 8 tablas y 47 columnas, todas documentadas: stg_medicamentos 5, stg_tickets 5, stg_ventas 6, dim_pacientes 4,
dim_medicamentos 5, fact_ventas_farmacia 6, fact_tickets_atencion 5 y aud_linaje_carga 11.
**/
select
    s.name as esquema,
    t.name as tabla,
    count(c.column_id) as num_columnas,
    count(ep.value) as num_columnas_documentadas
from sys.tables t
inner join sys.schemas s
    on t.schema_id = s.schema_id
inner join sys.columns c
    on t.object_id = c.object_id
left join sys.extended_properties ep
    on ep.major_id = t.object_id
    and ep.minor_id = c.column_id
    and ep.class = 1
    and ep.name = N'MS_Description'
group by
    s.name,
    t.name
order by
    s.name,
    t.name;


/**
Pregunta 13.4: Todas las tablas cumplen el estandar de nombres (minusculas y snake_case)?
collate Latin1_General_CS_AS hace la comparacion sensible a mayusculas.
R= 0 registros. Las 8 tablas y sus 47 columnas estan en minusculas.
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
Pregunta 13.5: Cuales son las llaves foraneas del modelo?
R= 3 llaves foraneas, todas en plata: fact_ventas_farmacia.id_paciente -> dim_pacientes,
fact_ventas_farmacia.ean_medicamento -> dim_medicamentos y fact_tickets_atencion.id_venta -> fact_ventas_farmacia.
**/
select
    object_name(fkc.parent_object_id) as tabla_hija,
    col_name(fkc.parent_object_id, fkc.parent_column_id) as columna_fk,
    object_name(fkc.referenced_object_id) as tabla_padre,
    col_name(fkc.referenced_object_id, fkc.referenced_column_id) as columna_pk
from sys.foreign_key_columns fkc
order by tabla_hija;
