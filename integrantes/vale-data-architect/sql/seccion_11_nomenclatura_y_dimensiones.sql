/**
11. NOMENCLATURA Y DIMENSIONES - VALE (Data Architect / SQL Specialist)
Clase 17, Paso 1 del taller: inventario de nombres y refactorizacion al estandar del equipo.
Estandar: minusculas, snake_case, prefijos dim_ (maestras), fact_ (transaccionales), stg_ (staging),
aud_ (auditoria) y abreviaturas id_, fch_ (fecha) y mto_ (monto).
**/

/**
Pregunta 11.1: Que tablas y columnas del Avance 1 no cumplen el estandar de minusculas?
collate Latin1_General_CS_AS hace la comparacion sensible a mayusculas (la base por defecto no distingue).
R= 20 registros: todas las columnas de Pacientes, Medicamentos, Ventas_Farmacia y Tickets_Atencion.
Ademas staging_ no es el prefijo estandar (stg_) y Fecha_Hora / Monto_Total_MXN no usan fch_ / mto_.
**/
select
    t.name as tabla,
    c.name as columna
from sys.tables t
inner join sys.columns c
    on t.object_id = c.object_id
where t.name collate Latin1_General_CS_AS <> lower(t.name)
    or c.name collate Latin1_General_CS_AS <> lower(c.name)
order by
    t.name,
    c.column_id;


/**
11.2 Refactorizacion con sp_rename
Primero las tablas y despues las columnas, usando ya el nombre nuevo de la tabla.
Los tipos de dato se revisaron y no requieren alter column (EAN varchar(13), montos decimal(10,2)).
**/
exec sp_rename 'Pacientes', 'dim_pacientes';
exec sp_rename 'Medicamentos', 'dim_medicamentos';
exec sp_rename 'Ventas_Farmacia', 'fact_ventas_farmacia';
exec sp_rename 'Tickets_Atencion', 'fact_tickets_atencion';
exec sp_rename 'staging_medicamentos', 'stg_medicamentos';
exec sp_rename 'staging_tickets', 'stg_tickets';

exec sp_rename 'dim_pacientes.ID_Paciente', 'id_paciente', 'COLUMN';
exec sp_rename 'dim_pacientes.Nombre', 'nombre', 'COLUMN';
exec sp_rename 'dim_pacientes.Apellido', 'apellido', 'COLUMN';
exec sp_rename 'dim_pacientes.Correo', 'correo', 'COLUMN';

exec sp_rename 'dim_medicamentos.EAN_Medicamento', 'ean_medicamento', 'COLUMN';
exec sp_rename 'dim_medicamentos.Nombre_Comercial', 'nombre_comercial', 'COLUMN';
exec sp_rename 'dim_medicamentos.Sustancia_Activa', 'sustancia_activa', 'COLUMN';
exec sp_rename 'dim_medicamentos.Requiere_Receta', 'requiere_receta', 'COLUMN';
exec sp_rename 'dim_medicamentos.Estatus_Alerta_Sanitaria', 'estatus_alerta_sanitaria', 'COLUMN';

exec sp_rename 'fact_ventas_farmacia.ID_Venta', 'id_venta', 'COLUMN';
exec sp_rename 'fact_ventas_farmacia.Fecha_Hora', 'fch_venta', 'COLUMN';
exec sp_rename 'fact_ventas_farmacia.ID_Paciente', 'id_paciente', 'COLUMN';
exec sp_rename 'fact_ventas_farmacia.EAN_Medicamento', 'ean_medicamento', 'COLUMN';
exec sp_rename 'fact_ventas_farmacia.Cantidad_Piezas', 'cantidad_piezas', 'COLUMN';
exec sp_rename 'fact_ventas_farmacia.Monto_Total_MXN', 'mto_total_mxn', 'COLUMN';

exec sp_rename 'fact_tickets_atencion.ID_Ticket', 'id_ticket', 'COLUMN';
exec sp_rename 'fact_tickets_atencion.ID_Venta', 'id_venta', 'COLUMN';
exec sp_rename 'fact_tickets_atencion.Motivo_Atencion', 'motivo_atencion', 'COLUMN';
exec sp_rename 'fact_tickets_atencion.Estatus_Ticket', 'estatus_ticket', 'COLUMN';
exec sp_rename 'fact_tickets_atencion.Tiempo_Resolucion_Min', 'tiempo_resolucion_min', 'COLUMN';


/**
11.3 Tabla nueva: aud_linaje_carga
Bitacora de auditoria del pipeline. No tiene llaves foraneas hacia las otras tablas, por lo que no altera
el modelo existente; guarda los metadatos operativos (fuente, fecha de carga, regla aplicada) que pide la Clase 17.
Daniel la llena en la seccion 12.
**/
create table aud_linaje_carga (
    id_carga int identity(1,1) primary key,
    fase_pipeline varchar(20) not null,
    nombre_fuente varchar(100) not null,
    tipo_fuente varchar(10) not null,
    tabla_origen varchar(128) null,
    tabla_destino varchar(128) not null,
    regla_aplicada varchar(300) not null,
    num_registros_origen int not null,
    num_registros_destino int not null,
    fch_carga datetime2 not null,
    responsable_carga varchar(50) not null
);


/**
11.4 Vistas y procedimientos del Avance 1
sp_rename no actualiza el texto de las vistas ni de los procedimientos: siguen apuntando a Pacientes,
Ventas_Farmacia, etc. y fallarian. Se eliminan los 6 objetos; Vale recrea los suyos aqui y Max los suyos en la seccion 13.
**/
if object_id('vw_KPI_Sustancia_Activa', 'V') is not null
    drop view vw_KPI_Sustancia_Activa;

if object_id('vw_Vista360_Farmacia', 'V') is not null
    drop view vw_Vista360_Farmacia;

if object_id('vw_Ventas_Operativas', 'V') is not null
    drop view vw_Ventas_Operativas;

if object_id('sp_InsertarPaciente', 'P') is not null
    drop procedure sp_InsertarPaciente;

if object_id('sp_ConsultarPacientePorID', 'P') is not null
    drop procedure sp_ConsultarPacientePorID;

if object_id('sp_Historial_Paciente', 'P') is not null
    drop procedure sp_Historial_Paciente;
go


/**
11.5 Vista 1 (Operativa) con nombres estandar
**/
create view vw_ventas_operativas as
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
from fact_ventas_farmacia v
inner join dim_pacientes p
    on v.id_paciente = p.id_paciente
inner join dim_medicamentos m
    on v.ean_medicamento = m.ean_medicamento;
go


/**
11.6 SP1 - Insercion controlada de paciente
**/
create procedure sp_insertar_paciente
    @id_paciente varchar(10),
    @nombre varchar(100),
    @apellido varchar(100),
    @correo varchar(150)
as
begin
    set nocount on;

    set @id_paciente = ltrim(rtrim(@id_paciente));
    set @nombre = ltrim(rtrim(@nombre));
    set @apellido = ltrim(rtrim(@apellido));
    set @correo = lower(ltrim(rtrim(@correo)));

    if exists (
        select 1
        from dim_pacientes
        where id_paciente = @id_paciente
    )
    begin
        raiserror('El paciente ya existe en la base de datos.', 16, 1);
        return;
    end;

    insert into dim_pacientes (id_paciente, nombre, apellido, correo)
    values (@id_paciente, @nombre, @apellido, @correo);
end;
go


/**
11.7 SP2 - Consulta de paciente por ID
**/
create procedure sp_consultar_paciente_por_id
    @id_paciente varchar(10)
as
begin
    set nocount on;

    set @id_paciente = ltrim(rtrim(@id_paciente));

    select
        id_paciente,
        ltrim(rtrim(nombre)) as nombre,
        ltrim(rtrim(apellido)) as apellido,
        coalesce(lower(ltrim(rtrim(correo))), 'sin correo registrado') as correo
    from dim_pacientes
    where id_paciente = @id_paciente;
end;
go


/**
11.8 Propiedades extendidas de las dimensiones (dim_pacientes y dim_medicamentos)
**/
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Dimensión maestra de pacientes de la farmacia. Centraliza la identidad de cada paciente para la Vista 360 y para los procedimientos de alta, consulta e historial de compras.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'dim_pacientes';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador único del paciente con formato PAC-###, tomado del ID de cliente de la base operacional de ventas.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'dim_pacientes',
    @level2type = N'COLUMN', @level2name = N'id_paciente';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Nombre(s) del paciente. Se guarda sin espacios al inicio ni al final para evitar duplicados visuales.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'dim_pacientes',
    @level2type = N'COLUMN', @level2name = N'nombre';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Apellido(s) del paciente. Se guarda sin espacios al inicio ni al final.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'dim_pacientes',
    @level2type = N'COLUMN', @level2name = N'apellido';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Correo electrónico de contacto del paciente, en minúsculas. Es opcional; cuando falta, los reportes muestran "sin correo registrado".',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'dim_pacientes',
    @level2type = N'COLUMN', @level2name = N'correo';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Dimensión maestra del catálogo de medicamentos, homologado desde la fuente COFEPRIS (JSON). Define la clasificación regulatoria y el estatus sanitario de cada producto.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'dim_medicamentos';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Código de barras EAN-13 del medicamento. Se guarda como texto de 13 caracteres para no perder ceros a la izquierda y es la llave para cruzar ventas con el catálogo.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'dim_medicamentos',
    @level2type = N'COLUMN', @level2name = N'ean_medicamento';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Nombre comercial o de marca con su presentación (ej. Tempra Forte 650mg); es el nombre que ve el cliente en mostrador.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'dim_medicamentos',
    @level2type = N'COLUMN', @level2name = N'nombre_comercial';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Principio activo del medicamento. Agrupa productos equivalentes y es el eje de los indicadores de vw_kpi_sustancia_activa.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'dim_medicamentos',
    @level2type = N'COLUMN', @level2name = N'sustancia_activa';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Indicador regulatorio de venta: SI = requiere receta médica, NO = venta libre. Permite medir el cumplimiento normativo del ingreso.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'dim_medicamentos',
    @level2type = N'COLUMN', @level2name = N'requiere_receta';

exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Estatus sanitario del producto según COFEPRIS (ej. Vigente, Bajo Revisión). Permite identificar ventas de productos con alerta.',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'dim_medicamentos',
    @level2type = N'COLUMN', @level2name = N'estatus_alerta_sanitaria';


/**
Pregunta 11.9: Los objetos de Vale funcionan con los nombres nuevos?
R= vw_ventas_operativas regresa 5 filas. sp_consultar_paciente_por_id 'PAC-101' regresa 1 fila con correo "sin correo registrado".
**/
select
    count(*) as filas_vista_operativa
from vw_ventas_operativas;

exec sp_consultar_paciente_por_id 'PAC-101';
