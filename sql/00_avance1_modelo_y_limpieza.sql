/**
UNIVERSIDAD IBEROAMERICANA LEON - INTEGRACION DE DATOS
PROYECTO INTEGRADOR - ENTREGA 2: METADATOS, DICCIONARIO DE DATOS Y LINAJE
EQUIPO 3: Operaciones Farmaceuticas y Servicio (Vista 360)

Integrantes y roles:
    Mariano  - Project Manager / Communicator (integracion, linaje y cierre)
    Vale     - Data Architect / SQL Specialist (nomenclatura, tabla nueva, dimensiones, Vista 1, SP1, SP2)
    Daniel   - Data Engineer / Pipeline Lead (registro de linaje, documentacion de staging y bitacora)
    Bruno    - Data Quality & QA Specialist (diccionario de datos, validaciones, preguntas de la Clase 17)
    Max      - BI & Analytics Specialist (hechos, Vista 2, Vista 3, SP3, capa semantica)

Orden del script:
    0 a 10.  Avance 1 completo (modelo, staging, limpieza, carga, vistas, procedimientos y preguntas de negocio)
    11. Nomenclatura y dimensiones - Vale
    12. Linaje y staging - Daniel
    13. Hechos y capa semantica - Max
    14. Diccionario de datos y calidad - Bruno
    15. Linaje y cierre - Mariano

Nota: el script borra y vuelve a crear FarmaciaBI para que todos tengan la misma base. Cierren cualquier otra
pestana de SSMS conectada a FarmaciaBI antes de ejecutarlo completo (F5).
Se usa go solo donde SQL Server lo exige (create view y create procedure deben ir solos en su lote).
**/


/**
0. BASE DE DATOS
**/
use master;
go

if db_id('FarmaciaBI') is not null
    drop database FarmaciaBI;
go

create database FarmaciaBI;
go

use FarmaciaBI;
go


/**
1. MODELO RELACIONAL (DDL) - VALE
Tablas maestras: Pacientes, Medicamentos.
Tablas transaccionales: Ventas_Farmacia, Tickets_Atencion.
Cardinalidades: Pacientes 1:N Ventas_Farmacia, Medicamentos 1:N Ventas_Farmacia, Ventas_Farmacia 1:N Tickets_Atencion.
Supuesto del equipo: el dataset solo trae ID_Cliente dentro de las ventas; se crea la tabla maestra Pacientes
(con Nombre, Apellido y Correo) para poder construir la Vista 360 y los procedimientos de paciente.
**/
create table Pacientes (
    ID_Paciente varchar(10) primary key,
    Nombre varchar(100) not null,
    Apellido varchar(100) not null,
    Correo varchar(150) null
);

create table Medicamentos (
    EAN_Medicamento varchar(13) primary key,
    Nombre_Comercial varchar(150) not null,
    Sustancia_Activa varchar(150) not null,
    Requiere_Receta varchar(2) not null,
    Estatus_Alerta_Sanitaria varchar(50) null
);

create table Ventas_Farmacia (
    ID_Venta varchar(10) primary key,
    Fecha_Hora datetime not null,
    ID_Paciente varchar(10) not null,
    EAN_Medicamento varchar(13) not null,
    Cantidad_Piezas int not null,
    Monto_Total_MXN decimal(10,2) not null,
    foreign key (ID_Paciente) references Pacientes(ID_Paciente),
    foreign key (EAN_Medicamento) references Medicamentos(EAN_Medicamento)
);

create table Tickets_Atencion (
    ID_Ticket varchar(10) primary key,
    ID_Venta varchar(10) not null,
    Motivo_Atencion varchar(100) not null,
    Estatus_Ticket varchar(50) not null,
    Tiempo_Resolucion_Min int null,
    foreign key (ID_Venta) references Ventas_Farmacia(ID_Venta)
);


/**
2. INGESTA DE FUENTES A STAGING - DANIEL
Las fuentes externas (catalogo COFEPRIS en JSON y tickets en CSV) se cargan primero a tablas staging,
sin restricciones, para conservar los datos tal como llegan y poder diagnosticarlos antes de limpiarlos.
El EAN se recibe como texto para no perder ceros a la izquierda.
**/
create table staging_medicamentos (
    ean_medicamento varchar(50),
    nombre_comercial varchar(150),
    sustancia_activa varchar(150),
    requiere_receta varchar(20),
    estatus_alerta_sanitaria varchar(100)
);

create table staging_tickets (
    id_ticket varchar(20),
    id_venta varchar(20),
    motivo_atencion varchar(150),
    estatus_ticket varchar(100),
    tiempo_resolucion_min int null
);

insert into staging_medicamentos
values
('7501000001010', 'Tempra Forte 650mg', 'Paracetamol', 'NO', 'Vigente'),
('7501000002020', 'Amoxil 500mg', 'Amoxicilina', 'SI', 'Vigente'),
('7501000003030', 'Bio-Grip Restructurado', 'Antihistamínico Compuesto', 'NO', 'Bajo Revisión');

insert into staging_tickets
values
('TCK-301', 'FAR-901', 'Cobro Incorrecto', ' Cerrado ', 15),
('TCK-302', 'FAR-902', 'Surtido Incompleto', 'CERRADO', 25),
('TCK-303', 'FAR-903', 'Efecto Secundario Reportado', ' En Escalacion ', null),
('TCK-304', 'FAR-905', 'Duda de Posología', 'Cerrado', 10);


/**
3. FASE 1 - DIAGNOSTICO - BRUNO
Pregunta 1.1: Cuantos valores nulos tiene cada columna de los tickets crudos?
R= Solo Tiempo_Resolucion_Min tiene 1 nulo (TCK-303).
**/
select
    count(*) as Total_Registros,
    sum(case when id_ticket is null then 1 else 0 end) as Nulos_ID_Ticket,
    sum(case when id_venta is null then 1 else 0 end) as Nulos_ID_Venta,
    sum(case when motivo_atencion is null then 1 else 0 end) as Nulos_Motivo,
    sum(case when estatus_ticket is null then 1 else 0 end) as Nulos_Estatus,
    sum(case when tiempo_resolucion_min is null then 1 else 0 end) as Nulos_Tiempo
from staging_tickets;


/**
Pregunta 1.2: Que tickets tienen espacios extra al inicio o al final del estatus?
Se usa datalength porque SQL Server ignora los espacios finales al comparar con =.
R= 2 tickets: TCK-301 (" Cerrado ") y TCK-303 (" En Escalacion ").
**/
select
    id_ticket,
    '[' + estatus_ticket + ']' as Estatus_Visible,
    datalength(estatus_ticket) as Largo_Original,
    datalength(ltrim(rtrim(estatus_ticket))) as Largo_Sin_Espacios
from staging_tickets
where datalength(estatus_ticket) <> datalength(ltrim(rtrim(estatus_ticket)));


/**
Pregunta 1.3: De cuantas formas distintas esta escrito el mismo estatus?
R= "Cerrado" aparece de 3 formas: "Cerrado", " Cerrado " y "CERRADO". "En Escalacion" viene sin acento y con espacios.
**/
select
    id_ticket,
    '[' + estatus_ticket + ']' as Estatus_Visible
from staging_tickets
order by id_ticket;


/**
Pregunta 1.4: Todos los EAN del catalogo tienen 13 caracteres (sin perdida de ceros a la izquierda)?
R= 0 registros. Los 3 EAN tienen 13 caracteres.
**/
select
    ean_medicamento,
    len(ean_medicamento) as Largo_EAN
from staging_medicamentos
where len(ean_medicamento) <> 13;


/**
Pregunta 1.5: Hay tickets o medicamentos repetidos por reintentos de ingesta?
R= 0 registros en ambas tablas.
**/
select
    id_ticket,
    count(*) as Veces
from staging_tickets
group by id_ticket
having count(*) > 1;

select
    ean_medicamento,
    count(*) as Veces
from staging_medicamentos
group by ean_medicamento
having count(*) > 1;


/**
4. FASE 2 - ESTANDARIZACION - DANIEL
Se homologan las variantes del estatus: se quitan espacios (ltrim/rtrim), se normalizan mayusculas (lower)
y se unifica la categoria con acento: "Cerrado" y "En Escalación".
**/
update staging_tickets
set estatus_ticket = 'Cerrado'
where lower(ltrim(rtrim(estatus_ticket))) = 'cerrado';

update staging_tickets
set estatus_ticket = 'En Escalación'
where lower(ltrim(rtrim(estatus_ticket))) = 'en escalacion';

update staging_tickets
set estatus_ticket = ltrim(rtrim(estatus_ticket));

update staging_medicamentos
set ean_medicamento = ltrim(rtrim(ean_medicamento)),
    nombre_comercial = ltrim(rtrim(nombre_comercial)),
    sustancia_activa = ltrim(rtrim(sustancia_activa)),
    requiere_receta = upper(ltrim(rtrim(requiere_receta)));


/**
5. FASE 3 - DEDUPLICACION - DANIEL
row_number() numera las filas de cada ticket y de cada EAN; cualquier fila con numero mayor a 1
seria un registro repetido por reintento de ingesta y se elimina.
R= Todas las filas quedan con numero_fila = 1; no se elimina ningun registro.
**/
with duplicados as (
    select
        id_ticket,
        row_number() over (partition by id_ticket order by id_ticket) as numero_fila
    from staging_tickets
)
delete from duplicados
where numero_fila > 1;

with duplicados_medicamentos as (
    select
        ean_medicamento,
        row_number() over (partition by ean_medicamento order by ean_medicamento) as numero_fila
    from staging_medicamentos
)
delete from duplicados_medicamentos
where numero_fila > 1;


/**
6. FASE 4 - VALIDACION Y ENRIQUECIMIENTO
6.1 Imputacion de valores faltantes - DANIEL
El tiempo nulo de TCK-303 se completa con coalesce usando el promedio de los tiempos disponibles.
R= (15 + 25 + 10) / 3 = 16.67, que queda en 16 por ser columna int. TCK-303 = 16 minutos.
**/
update staging_tickets
set tiempo_resolucion_min = coalesce(
    tiempo_resolucion_min,
    (select avg(tiempo_resolucion_min) from staging_tickets where tiempo_resolucion_min is not null)
);


/**
6.2 Carga a las tablas finales - DANIEL
Catalogo de medicamentos (EAN homologado a varchar(13)), pacientes, ventas de la base operacional
y tickets ya limpios.
Las fechas van en formato yyyymmdd: SQL Server lo lee igual en cualquier idioma. Con un login en espanol,
'2026-08-01' en una columna datetime se leeria como 8 de enero y el historial de agosto saldria vacio.
**/
insert into Medicamentos (
    EAN_Medicamento,
    Nombre_Comercial,
    Sustancia_Activa,
    Requiere_Receta,
    Estatus_Alerta_Sanitaria
)
select
    cast(ean_medicamento as varchar(13)),
    nombre_comercial,
    sustancia_activa,
    requiere_receta,
    estatus_alerta_sanitaria
from staging_medicamentos;

insert into Pacientes (ID_Paciente, Nombre, Apellido, Correo)
values
('PAC-101', 'Paciente', '101', null),
('PAC-102', 'Paciente', '102', null),
('PAC-103', 'Paciente', '103', null),
('PAC-104', 'Paciente', '104', null);

insert into Ventas_Farmacia (
    ID_Venta,
    Fecha_Hora,
    ID_Paciente,
    EAN_Medicamento,
    Cantidad_Piezas,
    Monto_Total_MXN
)
values
('FAR-901', '20260801 08:30:00', 'PAC-101', '7501000001010', 2, 180.00),
('FAR-902', '20260801 10:15:00', 'PAC-102', '7501000002020', 1, 450.00),
('FAR-903', '20260802 13:40:00', 'PAC-103', '7501000003030', 3, 1200.00),
('FAR-904', '20260802 17:00:00', 'PAC-101', '7501000001010', 1, 90.00),
('FAR-905', '20260803 19:20:00', 'PAC-104', '7501000002020', 2, 900.00);

insert into Tickets_Atencion (
    ID_Ticket,
    ID_Venta,
    Motivo_Atencion,
    Estatus_Ticket,
    Tiempo_Resolucion_Min
)
select
    id_ticket,
    id_venta,
    motivo_atencion,
    estatus_ticket,
    tiempo_resolucion_min
from staging_tickets;


/**
6.3 Validaciones de calidad - BRUNO
Pregunta 6.3.1: Existe algun monto negativo? abs() muestra el valor corregido en caso de encontrarlo.
R= 0 registros. Todos los montos son positivos.
**/
select
    ID_Venta,
    Monto_Total_MXN,
    abs(Monto_Total_MXN) as Monto_Corregido
from Ventas_Farmacia
where Monto_Total_MXN < 0;


/**
Pregunta 6.3.2: Hay cantidades o montos en cero o negativos, o fechas fuera de agosto 2026?
R= 0 registros.
**/
select
    ID_Venta,
    Fecha_Hora,
    Cantidad_Piezas,
    Monto_Total_MXN
from Ventas_Farmacia
where Cantidad_Piezas <= 0
    or Monto_Total_MXN <= 0
    or Fecha_Hora < '20260801'
    or Fecha_Hora >= '20260901';


/**
Pregunta 6.3.3: El precio por pieza de cada medicamento es el mismo en todas sus ventas?
R= Si. Tempra $90, Amoxil $450 y Bio-Grip $400; el minimo y el maximo coinciden.
**/
select
    m.Nombre_Comercial,
    min(v.Monto_Total_MXN / v.Cantidad_Piezas) as Precio_Minimo,
    max(v.Monto_Total_MXN / v.Cantidad_Piezas) as Precio_Maximo
from Ventas_Farmacia v
left join Medicamentos m
    on v.EAN_Medicamento = m.EAN_Medicamento
group by m.Nombre_Comercial;


/**
Pregunta 6.3.4: Hay ventas cuyo EAN no exista en el catalogo (integracion con left join)?
R= 0 registros. Las 5 ventas encuentran su medicamento.
**/
select
    v.ID_Venta,
    v.EAN_Medicamento
from Ventas_Farmacia v
left join Medicamentos m
    on v.EAN_Medicamento = m.EAN_Medicamento
where m.EAN_Medicamento is null;


/**
Pregunta 6.3.5: Que ventas no tienen ticket de atencion (integracion con left join)?
R= Solo FAR-904. Es normal: no toda venta genera una queja.
**/
select
    v.ID_Venta,
    t.ID_Ticket
from Ventas_Farmacia v
left join Tickets_Atencion t
    on v.ID_Venta = t.ID_Venta
where t.ID_Ticket is null;


/**
Pregunta 6.3.6: Despues de la limpieza, cuantos valores distintos quedan en el estatus?
R= Solo 2: "Cerrado" (3 tickets) y "En Escalación" (1 ticket), sin espacios.
**/
select
    '[' + Estatus_Ticket + ']' as Estatus_Visible,
    count(*) as Num_Tickets
from Tickets_Atencion
group by Estatus_Ticket;


/**
Pregunta 6.3.7: Quedan tiempos de resolucion nulos y que valor recibio TCK-303?
R= 0 nulos. TCK-303 quedo con 16 minutos.
**/
select
    ID_Ticket,
    Tiempo_Resolucion_Min
from Tickets_Atencion
where Tiempo_Resolucion_Min is null
    or ID_Ticket = 'TCK-303';


/**
Pregunta 6.3.8: Cada tabla final tiene el numero de registros esperado?
R= Pacientes 4, Ventas 5, Medicamentos 3, Tickets 4. Ingreso total $2,820.
**/
select
    (select count(*) from Pacientes) as Pacientes,
    (select count(*) from Ventas_Farmacia) as Ventas,
    (select count(*) from Medicamentos) as Medicamentos,
    (select count(*) from Tickets_Atencion) as Tickets,
    (select sum(Monto_Total_MXN) from Ventas_Farmacia) as Ingreso_Total;
go


/**
7. VISTAS ANALITICAS
7.1 Vista 1 (Operativa) - VALE
Consolida cada venta ya procesada con su paciente y su medicamento, con textos limpios y precio unitario.
**/
create view vw_Ventas_Operativas as
select
    v.ID_Venta,
    v.Fecha_Hora,
    v.ID_Paciente,
    ltrim(rtrim(p.Nombre)) as Nombre,
    ltrim(rtrim(p.Apellido)) as Apellido,
    v.EAN_Medicamento,
    ltrim(rtrim(m.Nombre_Comercial)) as Medicamento,
    ltrim(rtrim(m.Sustancia_Activa)) as Sustancia_Activa,
    m.Requiere_Receta,
    m.Estatus_Alerta_Sanitaria,
    v.Cantidad_Piezas,
    v.Monto_Total_MXN,
    cast(v.Monto_Total_MXN / nullif(v.Cantidad_Piezas, 0) as decimal(10,2)) as Precio_Unitario
from Ventas_Farmacia v
inner join Pacientes p
    on v.ID_Paciente = p.ID_Paciente
inner join Medicamentos m
    on v.EAN_Medicamento = m.EAN_Medicamento;
go


/**
7.2 Vista 2 (Analitica 360) - MAX
Une en una fila al paciente, la venta, el medicamento y la queja. El left join hacia Tickets_Atencion
conserva las ventas sin queja (FAR-904) con los campos del ticket en null.
**/
create view vw_Vista360_Farmacia as
select
    p.ID_Paciente,
    ltrim(rtrim(p.Nombre)) + ' ' + ltrim(rtrim(p.Apellido)) as Nombre_Paciente,
    v.ID_Venta,
    v.Fecha_Hora,
    v.EAN_Medicamento,
    m.Nombre_Comercial,
    m.Sustancia_Activa,
    m.Requiere_Receta,
    m.Estatus_Alerta_Sanitaria,
    v.Cantidad_Piezas,
    v.Monto_Total_MXN,
    t.ID_Ticket,
    t.Motivo_Atencion,
    t.Estatus_Ticket,
    t.Tiempo_Resolucion_Min
from Pacientes p
inner join Ventas_Farmacia v
    on p.ID_Paciente = v.ID_Paciente
inner join Medicamentos m
    on v.EAN_Medicamento = m.EAN_Medicamento
left join Tickets_Atencion t
    on v.ID_Venta = t.ID_Venta;
go


/**
7.3 Vista 3 (Resumen KPI) - MAX
Resumen ejecutivo por sustancia activa: ventas, piezas, ingreso, ticket promedio, quejas y tiempo promedio de resolucion.
**/
create view vw_KPI_Sustancia_Activa as
select
    Sustancia_Activa,
    Requiere_Receta,
    Estatus_Alerta_Sanitaria,
    count(ID_Venta) as Num_Ventas,
    sum(Cantidad_Piezas) as Piezas_Vendidas,
    sum(Monto_Total_MXN) as Ingreso_Total_MXN,
    avg(Monto_Total_MXN) as Ticket_Promedio_MXN,
    count(ID_Ticket) as Num_Quejas,
    avg(Tiempo_Resolucion_Min * 1.0) as Tiempo_Promedio_Resolucion_Min
from vw_Vista360_Farmacia
group by
    Sustancia_Activa,
    Requiere_Receta,
    Estatus_Alerta_Sanitaria;
go


/**
8. PROCEDIMIENTOS ALMACENADOS
8.1 SP1 - Insercion controlada de paciente - VALE
Limpia espacios (ltrim/rtrim), pasa el correo a minusculas (lower) y rechaza IDs repetidos (if exists / raiserror).
**/
create procedure sp_InsertarPaciente
    @ID_Paciente varchar(10),
    @Nombre varchar(100),
    @Apellido varchar(100),
    @Correo varchar(150)
as
begin
    set nocount on;

    set @ID_Paciente = ltrim(rtrim(@ID_Paciente));
    set @Nombre = ltrim(rtrim(@Nombre));
    set @Apellido = ltrim(rtrim(@Apellido));
    set @Correo = lower(ltrim(rtrim(@Correo)));

    if exists (
        select 1
        from Pacientes
        where ID_Paciente = @ID_Paciente
    )
    begin
        raiserror('El paciente ya existe en la base de datos.', 16, 1);
        return;
    end;

    insert into Pacientes (ID_Paciente, Nombre, Apellido, Correo)
    values (@ID_Paciente, @Nombre, @Apellido, @Correo);
end;
go


/**
8.2 SP2 - Consulta de paciente por ID - VALE
Devuelve los datos limpios del paciente; si no tiene correo muestra un valor por defecto (coalesce).
**/
create procedure sp_ConsultarPacientePorID
    @ID_Paciente varchar(10)
as
begin
    set nocount on;

    set @ID_Paciente = ltrim(rtrim(@ID_Paciente));

    select
        ID_Paciente,
        ltrim(rtrim(Nombre)) as Nombre,
        ltrim(rtrim(Apellido)) as Apellido,
        coalesce(lower(ltrim(rtrim(Correo))), 'sin correo registrado') as Correo
    from Pacientes
    where ID_Paciente = @ID_Paciente;
end;
go


/**
8.3 SP3 - Historial de compras de un paciente por rango de fechas - MAX
Cruza la tabla maestra con la transaccional (inner join) y devuelve las compras en orden cronologico.
**/
create procedure sp_Historial_Paciente
    @ID_Paciente varchar(10),
    @FechaInicio date,
    @FechaFin date
as
begin
    set nocount on;

    select
        p.ID_Paciente,
        ltrim(rtrim(p.Nombre)) + ' ' + ltrim(rtrim(p.Apellido)) as Nombre_Paciente,
        v.ID_Venta,
        v.Fecha_Hora,
        m.Nombre_Comercial,
        m.Sustancia_Activa,
        v.Cantidad_Piezas,
        v.Monto_Total_MXN
    from Pacientes p
    inner join Ventas_Farmacia v
        on p.ID_Paciente = v.ID_Paciente
    inner join Medicamentos m
        on v.EAN_Medicamento = m.EAN_Medicamento
    where p.ID_Paciente = @ID_Paciente
        and cast(v.Fecha_Hora as date) between @FechaInicio and @FechaFin
    order by v.Fecha_Hora;
end;
go


/**
9. PRUEBAS DE PROCEDIMIENTOS Y VISTAS - BRUNO
9.1 SP1: insertar un paciente nuevo con espacios y mayusculas, insertarlo otra vez y borrarlo.
R= Se guarda [PAC-105], [Juan], [Perez], [juan.perez@gmail.com]. La segunda ejecucion manda
el mensaje "El paciente ya existe en la base de datos." (resultado esperado).
**/
exec sp_InsertarPaciente '  PAC-105 ', '  Juan ', ' Perez  ', ' JUAN.PEREZ@GMAIL.COM ';

exec sp_InsertarPaciente 'PAC-105', 'Juan', 'Perez', null;

select
    '[' + ID_Paciente + ']' as ID_Visible,
    '[' + Nombre + ']' as Nombre_Visible,
    '[' + Apellido + ']' as Apellido_Visible,
    '[' + Correo + ']' as Correo_Visible
from Pacientes
where ID_Paciente = 'PAC-105';

delete from Pacientes
where ID_Paciente = 'PAC-105';


/**
9.2 SP2: consultar un paciente existente y uno inexistente.
R= PAC-101 regresa 1 fila con Correo = "sin correo registrado". PAC-999 regresa 0 filas.
**/
exec sp_ConsultarPacientePorID 'PAC-101';

exec sp_ConsultarPacientePorID 'PAC-999';


/**
9.3 SP3: historial de PAC-101 en agosto y en septiembre 2026.
R= Agosto regresa 2 filas (FAR-901 y FAR-904). Septiembre regresa 0 filas.
**/
exec sp_Historial_Paciente 'PAC-101', '2026-08-01', '2026-08-31';

exec sp_Historial_Paciente 'PAC-101', '2026-09-01', '2026-09-30';


/**
9.4 Cuadre de las vistas contra las tablas.
R= Vista 1: 5 filas. Vista 360: 5 filas y $2,820, con FAR-904 sin ticket. Vista KPI: 3 filas, $2,820 y 4 quejas.
**/
select
    count(*) as Filas_Vista1
from vw_Ventas_Operativas;

select
    count(*) as Filas_Vista360,
    sum(Monto_Total_MXN) as Ingreso_Vista360
from vw_Vista360_Farmacia;

select
    ID_Venta,
    ID_Ticket
from vw_Vista360_Farmacia
where ID_Ticket is null;

select
    count(*) as Filas_KPI,
    sum(Ingreso_Total_MXN) as Ingreso_KPI,
    sum(Num_Quejas) as Quejas_KPI
from vw_KPI_Sustancia_Activa;


/**
10. PREGUNTAS DE NEGOCIO - MAX
Pregunta 1 - Cumplimiento normativo: que porcentaje del ingreso proviene de medicamentos con receta contra venta libre?
R= Con receta (Amoxil) $1,350 = 47.87%. Venta libre (Tempra y Bio-Grip) $1,470 = 52.13%. Ingreso total $2,820.
**/
select
    Requiere_Receta,
    sum(Monto_Total_MXN) as Ingreso_MXN,
    round(sum(Monto_Total_MXN) * 100.0 / (select sum(Monto_Total_MXN) from Ventas_Farmacia), 2) as Porcentaje_Ingreso
from vw_Vista360_Farmacia
group by Requiere_Receta;


/**
Pregunta 2 - Alertas sanitarias: cual es el monto de venta acumulado de productos bajo revision o con alerta sanitaria?
R= Bio-Grip Restructurado (Bajo Revisión) acumula $1,200, el 42.55% del ingreso total.
**/
select
    Nombre_Comercial,
    Estatus_Alerta_Sanitaria,
    sum(Monto_Total_MXN) as Monto_Acumulado_MXN
from vw_Vista360_Farmacia
where Estatus_Alerta_Sanitaria <> 'Vigente'
group by
    Nombre_Comercial,
    Estatus_Alerta_Sanitaria;


/**
Pregunta 3 - Quejas por principio activo: que sustancias generan mas tickets por efecto secundario o surtido incompleto?
R= Empatan con 1 ticket cada una: Amoxicilina (Surtido Incompleto) y Antihistamínico Compuesto (Efecto Secundario Reportado).
**/
select
    Sustancia_Activa,
    Motivo_Atencion,
    count(ID_Ticket) as Num_Tickets
from vw_Vista360_Farmacia
where Motivo_Atencion in ('Efecto Secundario Reportado', 'Surtido Incompleto')
group by
    Sustancia_Activa,
    Motivo_Atencion
order by Num_Tickets desc;


/**
Pregunta 4 - Eficiencia en soporte: cual es el tiempo promedio de resolucion tras imputar y como varia por tipo de queja?
R= Promedio general 16.50 min. Surtido Incompleto 25, Efecto Secundario Reportado 16 (imputado),
Cobro Incorrecto 15 y Duda de Posología 10.
**/
select
    Motivo_Atencion,
    count(ID_Ticket) as Num_Tickets,
    avg(Tiempo_Resolucion_Min * 1.0) as Tiempo_Promedio_Min
from Tickets_Atencion
group by Motivo_Atencion
order by Tiempo_Promedio_Min desc;

select
    avg(Tiempo_Resolucion_Min * 1.0) as Tiempo_Promedio_General_Min
from Tickets_Atencion;
