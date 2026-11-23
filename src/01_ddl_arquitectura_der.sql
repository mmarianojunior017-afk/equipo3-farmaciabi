/**
EQUIPO 3 - FarmaciaBI | Integracion de Datos | Universidad Iberoamericana Leon
01_ddl_arquitectura_der.sql
Base de datos, esquemas bronce / plata / oro y tablas (DDL)

Crea la base FarmaciaBI (la borra y la vuelve a crear), los tres esquemas de la arquitectura Medallon y las tablas
con sus llaves primarias, foraneas y restricciones CHECK. Al final documenta cada tabla y columna con MS_Description.
Cierre cualquier otra pestana de SSMS conectada a FarmaciaBI antes de ejecutarlo.

Roles: Vale (esquemas, DER, llaves) y Bruno (restricciones de calidad y descripciones).

Orden de ejecucion: 01 -> 02 -> 03 -> 04 (SQL Server 2019, SSMS). Cada archivo puede ejecutarse completo con F5.
**/


/**
0. BASE DE DATOS
**/
use master;
go

if db_id('FarmaciaBI') is not null
begin
    alter database FarmaciaBI set single_user with rollback immediate;
    drop database FarmaciaBI;
end;
go

create database FarmaciaBI;
go

use FarmaciaBI;
go


/**
1. ESQUEMAS DE LA ARQUITECTURA MEDALLON
bronce = ingesta cruda, plata = transformacion y calidad, oro = consumo para BI.
create schema debe ir solo en su lote, por eso lleva go.
**/
create schema bronce;
go

create schema plata;
go

create schema oro;
go


/**
2. CAPA BRONCE - tablas espejo de las fuentes
Reciben los datos tal como llegan, sin llaves ni restricciones, para poder diagnosticarlos antes de limpiarlos.
Las ventas llegan como texto (fecha, cantidad y monto) y se convierten con try_convert al pasar a plata.
El EAN se recibe como texto para no perder ceros a la izquierda.
**/
create table bronce.stg_medicamentos (
    ean_medicamento varchar(50),
    nombre_comercial varchar(150),
    sustancia_activa varchar(150),
    requiere_receta varchar(20),
    estatus_alerta_sanitaria varchar(100)
);

create table bronce.stg_tickets (
    id_ticket varchar(20),
    id_venta varchar(20),
    motivo_atencion varchar(150),
    estatus_ticket varchar(100),
    tiempo_resolucion_min int null
);

create table bronce.stg_ventas (
    id_venta varchar(20),
    fch_venta varchar(30),
    id_paciente varchar(20),
    ean_medicamento varchar(50),
    cantidad_piezas varchar(20),
    monto_total_mxn varchar(30)
);


/**
3. CAPA PLATA - modelo relacional limpio
Dimensiones: dim_pacientes y dim_medicamentos. Hechos: fact_ventas_farmacia y fact_tickets_atencion.
Cardinalidades: dim_pacientes 1:N fact_ventas_farmacia, dim_medicamentos 1:N fact_ventas_farmacia,
fact_ventas_farmacia 1:N fact_tickets_atencion.
Supuesto del equipo: el dataset solo trae el ID de cliente dentro de las ventas; dim_pacientes se genera a partir de el.
Restricciones CHECK: receta SI/NO, cantidad y monto mayores a cero, estatus de ticket dentro del catalogo.
**/
create table plata.dim_pacientes (
    id_paciente varchar(10) primary key,
    nombre varchar(100) not null,
    apellido varchar(100) not null,
    correo varchar(150) null
);

create table plata.dim_medicamentos (
    ean_medicamento varchar(13) primary key,
    nombre_comercial varchar(150) not null,
    sustancia_activa varchar(150) not null,
    requiere_receta varchar(2) not null,
    estatus_alerta_sanitaria varchar(50) null,
    constraint ck_dim_medicamentos_receta check (requiere_receta in ('SI', 'NO'))
);

create table plata.fact_ventas_farmacia (
    id_venta varchar(10) primary key,
    fch_venta datetime not null,
    id_paciente varchar(10) not null,
    ean_medicamento varchar(13) not null,
    cantidad_piezas int not null,
    mto_total_mxn decimal(10,2) not null,
    foreign key (id_paciente) references plata.dim_pacientes(id_paciente),
    foreign key (ean_medicamento) references plata.dim_medicamentos(ean_medicamento),
    constraint ck_fact_ventas_cantidad check (cantidad_piezas > 0),
    constraint ck_fact_ventas_monto check (mto_total_mxn > 0)
);

create table plata.fact_tickets_atencion (
    id_ticket varchar(10) primary key,
    id_venta varchar(10) not null,
    motivo_atencion varchar(100) not null,
    estatus_ticket varchar(50) not null,
    tiempo_resolucion_min int null,
    foreign key (id_venta) references plata.fact_ventas_farmacia(id_venta),
    constraint ck_fact_tickets_estatus check (estatus_ticket in ('Cerrado', 'En Escalación'))
);

/**
Bitacora de linaje del pipeline. No tiene llaves foraneas hacia las otras tablas.
**/
create table plata.aud_linaje_carga (
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
4. DOCUMENTACION DE METADATOS (MS_Description) - BRUNO
Descripcion de negocio de las 8 tablas y sus 47 columnas. Se consulta con sp_ObtenerDiccionarioDatos (archivo 04).
**/
-- bronce.stg_medicamentos
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tabla de la capa bronce que recibe el catálogo de medicamentos de COFEPRIS (JSON) tal como llega, sin restricciones, para diagnosticarlo antes de limpiarlo y cargarlo a plata.dim_medicamentos.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_medicamentos';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Código EAN recibido como texto desde la fuente, antes de validar que tenga 13 caracteres.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_medicamentos',
    @level2type = N'COLUMN', @level2name = N'ean_medicamento';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Nombre comercial del medicamento tal como viene en el JSON de COFEPRIS.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_medicamentos',
    @level2type = N'COLUMN', @level2name = N'nombre_comercial';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Sustancia activa del medicamento tal como viene en el JSON de COFEPRIS.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_medicamentos',
    @level2type = N'COLUMN', @level2name = N'sustancia_activa';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Indicador de receta médica recibido de la fuente; se estandariza a SI / NO en mayúsculas antes de la carga final.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_medicamentos',
    @level2type = N'COLUMN', @level2name = N'requiere_receta';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Estatus de alerta sanitaria reportado por la fuente, pendiente de validación.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_medicamentos',
    @level2type = N'COLUMN', @level2name = N'estatus_alerta_sanitaria';

-- bronce.stg_tickets
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tabla de la capa bronce que recibe los tickets de atención desde el archivo CSV sin restricciones, para diagnosticar nulos, espacios y variantes de escritura antes de cargarlos a plata.fact_tickets_atencion.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_tickets';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador del ticket tal como viene en el archivo CSV.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_tickets',
    @level2type = N'COLUMN', @level2name = N'id_ticket';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador de la venta asociada al ticket, aún sin validar contra fact_ventas_farmacia.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_tickets',
    @level2type = N'COLUMN', @level2name = N'id_venta';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Motivo de atención tal como viene en el archivo CSV.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_tickets',
    @level2type = N'COLUMN', @level2name = N'motivo_atencion';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Estatus del ticket con las variantes de la fuente (espacios, mayúsculas, sin acento); se homologa a Cerrado / En Escalación.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_tickets',
    @level2type = N'COLUMN', @level2name = N'estatus_ticket';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tiempo de resolución en minutos tal como viene en el CSV; puede llegar nulo y se imputa con el promedio.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_tickets',
    @level2type = N'COLUMN', @level2name = N'tiempo_resolucion_min';

-- bronce.stg_ventas
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tabla de la capa bronce que recibe las ventas de la base operacional (SQL) tal como llegan, todo como texto, para diagnosticarlas y convertirlas con try_convert antes de cargarlas a plata.fact_ventas_farmacia.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_ventas';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador de la venta tal como viene de la base operacional.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_ventas',
    @level2type = N'COLUMN', @level2name = N'id_venta';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Fecha y hora de la venta como texto en formato yyyymmdd hh:mm:ss; se convierte con try_convert al cargar a plata.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_ventas',
    @level2type = N'COLUMN', @level2name = N'fch_venta';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador del cliente (paciente) tal como viene en la venta; de aquí se generan los registros de plata.dim_pacientes.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_ventas',
    @level2type = N'COLUMN', @level2name = N'id_paciente';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Código EAN del medicamento vendido, recibido como texto.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_ventas',
    @level2type = N'COLUMN', @level2name = N'ean_medicamento';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Número de piezas recibido como texto; se convierte a entero y debe ser mayor a cero.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_ventas',
    @level2type = N'COLUMN', @level2name = N'cantidad_piezas';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Importe total en pesos recibido como texto; se convierte a decimal y debe ser mayor a cero.',
    @level0type = N'SCHEMA', @level0name = N'bronce',
    @level1type = N'TABLE', @level1name = N'stg_ventas',
    @level2type = N'COLUMN', @level2name = N'monto_total_mxn';

-- plata.dim_pacientes
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Dimensión maestra de pacientes de la farmacia. Centraliza la identidad de cada paciente para la Vista 360 y para los procedimientos de alta, consulta e historial de compras.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'dim_pacientes';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador único del paciente con formato PAC-###, tomado del ID de cliente de la base operacional de ventas.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'dim_pacientes',
    @level2type = N'COLUMN', @level2name = N'id_paciente';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Nombre(s) del paciente. Se guarda sin espacios al inicio ni al final para evitar duplicados visuales.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'dim_pacientes',
    @level2type = N'COLUMN', @level2name = N'nombre';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Apellido(s) del paciente. Se guarda sin espacios al inicio ni al final.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'dim_pacientes',
    @level2type = N'COLUMN', @level2name = N'apellido';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Correo electrónico de contacto del paciente, en minúsculas. Es opcional; cuando falta, los reportes muestran "sin correo registrado".',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'dim_pacientes',
    @level2type = N'COLUMN', @level2name = N'correo';

-- plata.dim_medicamentos
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Dimensión maestra del catálogo de medicamentos, homologado desde la fuente COFEPRIS (JSON). Define la clasificación regulatoria y el estatus sanitario de cada producto.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'dim_medicamentos';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Código de barras EAN-13 del medicamento. Se guarda como texto de 13 caracteres para no perder ceros a la izquierda y es la llave para cruzar ventas con el catálogo.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'dim_medicamentos',
    @level2type = N'COLUMN', @level2name = N'ean_medicamento';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Nombre comercial o de marca con su presentación (ej. Tempra Forte 650mg); es el nombre que ve el cliente en mostrador.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'dim_medicamentos',
    @level2type = N'COLUMN', @level2name = N'nombre_comercial';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Principio activo del medicamento. Agrupa productos equivalentes y es el eje de los indicadores de vw_kpi_sustancia_activa.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'dim_medicamentos',
    @level2type = N'COLUMN', @level2name = N'sustancia_activa';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Indicador regulatorio de venta: SI = requiere receta médica, NO = venta libre. Permite medir el cumplimiento normativo del ingreso.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'dim_medicamentos',
    @level2type = N'COLUMN', @level2name = N'requiere_receta';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Estatus sanitario del producto según COFEPRIS (ej. Vigente, Bajo Revisión). Permite identificar ventas de productos con alerta.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'dim_medicamentos',
    @level2type = N'COLUMN', @level2name = N'estatus_alerta_sanitaria';

-- plata.fact_ventas_farmacia
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tabla de hechos de ventas. Registra cada transacción del punto de venta y vincula al paciente con el medicamento, la cantidad y el importe cobrado.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador único de la venta con formato FAR-###.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia',
    @level2type = N'COLUMN', @level2name = N'id_venta';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Fecha y hora en que se registró la venta. Se usa para los historiales por rango de fechas.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia',
    @level2type = N'COLUMN', @level2name = N'fch_venta';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Paciente que realizó la compra. Llave foránea hacia dim_pacientes.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia',
    @level2type = N'COLUMN', @level2name = N'id_paciente';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Medicamento vendido. Llave foránea hacia dim_medicamentos.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia',
    @level2type = N'COLUMN', @level2name = N'ean_medicamento';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Número de piezas vendidas en la transacción. Regla de negocio: debe ser mayor a cero.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia',
    @level2type = N'COLUMN', @level2name = N'cantidad_piezas';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Importe total cobrado en pesos mexicanos (MXN). Regla de negocio: debe ser mayor a cero; es la base del ingreso en todos los KPI.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'fact_ventas_farmacia',
    @level2type = N'COLUMN', @level2name = N'mto_total_mxn';

-- plata.fact_tickets_atencion
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tabla de hechos de atención al cliente. Registra las quejas e incidencias que se originan en una venta y su tiempo de resolución.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'fact_tickets_atencion';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador único del ticket de atención con formato TCK-###.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'fact_tickets_atencion',
    @level2type = N'COLUMN', @level2name = N'id_ticket';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Venta que originó el ticket. Llave foránea hacia fact_ventas_farmacia; liga la queja con el paciente y el medicamento.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'fact_tickets_atencion',
    @level2type = N'COLUMN', @level2name = N'id_venta';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Motivo de la incidencia reportada (ej. Cobro Incorrecto, Surtido Incompleto, Efecto Secundario Reportado, Duda de Posología).',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'fact_tickets_atencion',
    @level2type = N'COLUMN', @level2name = N'motivo_atencion';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Estatus estandarizado del ticket en el flujo de atención: Cerrado o En Escalación.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'fact_tickets_atencion',
    @level2type = N'COLUMN', @level2name = N'estatus_ticket';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Minutos que tomó resolver el ticket. Los valores faltantes se imputaron con el promedio de los tickets con tiempo registrado.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'fact_tickets_atencion',
    @level2type = N'COLUMN', @level2name = N'tiempo_resolucion_min';

-- plata.aud_linaje_carga
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Bitácora de auditoría del pipeline ETL. Registra cada paso de ingesta, transformación y carga con su fuente, tabla destino, regla aplicada y conteo de registros para dar trazabilidad (linaje) a cada cifra.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Identificador autoincremental del paso de carga registrado en la bitácora.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'id_carga';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Fase del pipeline en la que ocurrió el paso: Ingesta (fuente a bronce) o Plata (bronce a plata).',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'fase_pipeline';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Fuente de negocio de donde provienen los datos (catálogo COFEPRIS, tickets de atención o base operacional de ventas).',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'nombre_fuente';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Formato técnico de la fuente: JSON, CSV o SQL.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'tipo_fuente';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tabla de la que se leyeron los datos. Es nula cuando el origen es un archivo o sistema externo.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'tabla_origen';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Tabla, con su esquema, en la que quedaron los datos después del paso.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'tabla_destino';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Regla de negocio o de limpieza que se aplicó en el paso (ej. homologación de estatus, imputación con promedio).',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'regla_aplicada';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Número de registros que entraron al paso; se compara con el destino para detectar pérdidas.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'num_registros_origen';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Número de registros que quedaron en la tabla destino al terminar el paso.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'num_registros_destino';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Fecha y hora en que se registró el paso en la bitácora (metadato operativo).',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'fch_carga';
exec sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Integrante del equipo responsable del paso, para saber a quién consultar en una auditoría.',
    @level0type = N'SCHEMA', @level0name = N'plata',
    @level1type = N'TABLE', @level1name = N'aud_linaje_carga',
    @level2type = N'COLUMN', @level2name = N'responsable_carga';
