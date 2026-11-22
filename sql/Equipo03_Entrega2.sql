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


/**
15. LINAJE Y CIERRE - MARIANO (Project Manager / Communicator)
Clase 17, lamina 8: cuando un reporte muestra una cifra inesperada, la forma de auditar la causa es el linaje.
Se rastrea de donde sale el ingreso de $2,820 que reporta la Vista 360.
**/

/**
Pregunta 15.1: De donde sale el ingreso de $2,820 de la Vista 360 y que reglas paso en el camino?
R= 5 pasos de 2 fuentes. Los montos y los pacientes vienen de la BD operacional de ventas (5 ventas validadas y
4 pacientes); el medicamento viene del catalogo COFEPRIS en JSON (ingesta, limpieza y carga a dim_medicamentos).
Cada paso tiene responsable, regla y conteo, asi que una diferencia se ubica en el paso exacto donde aparecio.
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
from aud_linaje_carga
where tabla_destino in ('stg_medicamentos', 'dim_medicamentos', 'dim_pacientes', 'fact_ventas_farmacia')
order by id_carga;


/**
Pregunta 15.2: Cual es el estado final de la documentacion del modelo?
R= 7 tablas y 41 columnas, todas documentadas: dim_pacientes 4, dim_medicamentos 5, fact_ventas_farmacia 6,
fact_tickets_atencion 5, stg_medicamentos 5, stg_tickets 5 y aud_linaje_carga 11.
**/
select
    t.name as tabla,
    count(c.column_id) as num_columnas,
    count(ep.value) as num_columnas_documentadas
from sys.tables t
inner join sys.columns c
    on t.object_id = c.object_id
left join sys.extended_properties ep
    on ep.major_id = t.object_id
    and ep.minor_id = c.column_id
    and ep.name = N'MS_Description'
group by t.name
order by t.name;


/**
Pregunta de reflexion: Por que es importante el linaje de los datos en las auditorias de cumplimiento?
R= Porque una auditoria no se conforma con la cifra final: pide demostrar de donde salio y que se le hizo.
El linaje deja ese rastro. En FarmaciaBI, aud_linaje_carga dice que fuente entro, que regla se aplico
(por ejemplo, la imputacion del tiempo de TCK-303 con el promedio), cuantos registros entraron y salieron y quien
fue responsable. Si COFEPRIS pregunta cuanto vendimos de un producto bajo revision, no basta con responder $1,200:
hay que mostrar que la cifra viene del catalogo oficial y de ventas validadas, sin registros perdidos. Sin linaje
el reporte es una afirmacion; con linaje es evidencia que se puede revisar.
**/
