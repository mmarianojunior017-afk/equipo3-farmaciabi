/**
13. HECHOS Y CAPA SEMANTICA - MAX (BI & Analytics Specialist)
Las vistas son la capa semantica de la Clase 17 (lamina 18): exponen a BI nombres unificados.
Se recrean Vista 2, Vista 3 y SP3 con los nombres estandar y se documentan las tablas de hechos.
**/

/**
13.1 Vista 2 (Analitica 360)
**/
create view vw_vista360_farmacia as
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
from dim_pacientes p
inner join fact_ventas_farmacia v
    on p.id_paciente = v.id_paciente
inner join dim_medicamentos m
    on v.ean_medicamento = m.ean_medicamento
left join fact_tickets_atencion t
    on v.id_venta = t.id_venta;
go


/**
13.2 Vista 3 (Resumen KPI)
**/
create view vw_kpi_sustancia_activa as
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
from vw_vista360_farmacia
group by
    sustancia_activa,
    requiere_receta,
    estatus_alerta_sanitaria;
go


/**
13.3 SP3 - Historial de compras de un paciente por rango de fechas
**/
create procedure sp_historial_paciente
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
    from dim_pacientes p
    inner join fact_ventas_farmacia v
        on p.id_paciente = v.id_paciente
    inner join dim_medicamentos m
        on v.ean_medicamento = m.ean_medicamento
    where p.id_paciente = @id_paciente
        and cast(v.fch_venta as date) between @fch_inicio and @fch_fin
    order by v.fch_venta;
end;
go


/**
13.4 Propiedades extendidas de las tablas de hechos (fact_ventas_farmacia y fact_tickets_atencion)
**/
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tabla de hechos de ventas. Registra cada transacción del punto de venta y vincula al paciente con el medicamento, la cantidad y el importe cobrado.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador único de la venta con formato FAR-###.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia',
    @level2type = N'COLUMN', @level2name = N'id_venta';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Fecha y hora en que se registró la venta. Se usa para los historiales por rango de fechas.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia',
    @level2type = N'COLUMN', @level2name = N'fch_venta';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Paciente que realizó la compra. Llave foránea hacia dim_pacientes.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia',
    @level2type = N'COLUMN', @level2name = N'id_paciente';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Medicamento vendido. Llave foránea hacia dim_medicamentos.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia',
    @level2type = N'COLUMN', @level2name = N'ean_medicamento';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Número de piezas vendidas en la transacción. Regla de negocio: debe ser mayor a cero.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia',
    @level2type = N'COLUMN', @level2name = N'cantidad_piezas';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Importe total cobrado en pesos mexicanos (MXN). Regla de negocio: debe ser mayor a cero; es la base del ingreso en todos los KPI.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia',
    @level2type = N'COLUMN', @level2name = N'mto_total_mxn';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tabla de hechos de atención al cliente. Registra las quejas e incidencias que se originan en una venta y su tiempo de resolución.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fact_tickets_atencion';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador único del ticket de atención con formato TCK-###.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fact_tickets_atencion',
    @level2type = N'COLUMN', @level2name = N'id_ticket';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Venta que originó el ticket. Llave foránea hacia fact_ventas_farmacia; liga la queja con el paciente y el medicamento.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fact_tickets_atencion',
    @level2type = N'COLUMN', @level2name = N'id_venta';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Motivo de la incidencia reportada (ej. Cobro Incorrecto, Surtido Incompleto, Efecto Secundario Reportado, Duda de Posología).',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fact_tickets_atencion',
    @level2type = N'COLUMN', @level2name = N'motivo_atencion';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Estatus estandarizado del ticket en el flujo de atención: Cerrado o En Escalación.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fact_tickets_atencion',
    @level2type = N'COLUMN', @level2name = N'estatus_ticket';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Minutos que tomó resolver el ticket. Los valores faltantes se imputaron con el promedio de los tickets con tiempo registrado.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fact_tickets_atencion',
    @level2type = N'COLUMN', @level2name = N'tiempo_resolucion_min';


/**
Pregunta 13.5: Despues de renombrar, la pregunta de negocio 1 (receta contra venta libre) da el mismo resultado?
R= Si. Con receta $1,350 = 47.87% y venta libre $1,470 = 52.13%. La refactorizacion no cambio ninguna cifra.
**/
select
    requiere_receta,
    sum(mto_total_mxn) as mto_ingreso_mxn,
    round(sum(mto_total_mxn) * 100.0 / (select sum(mto_total_mxn) from fact_ventas_farmacia), 2) as porcentaje_ingreso
from vw_vista360_farmacia
group by requiere_receta;
