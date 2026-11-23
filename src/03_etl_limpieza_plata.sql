/**
EQUIPO 3 - FarmaciaBI | Integracion de Datos | Universidad Iberoamericana Leon
03_etl_limpieza_plata.sql - Limpieza, deduplicacion, imputacion y carga (capa plata)

Estandariza textos (ltrim/rtrim/lower/upper), deduplica con row_number, imputa nulos con coalesce, carga las
tablas finales (fechas en formato yyyymmdd) y corre las validaciones de calidad y los conteos.

Orden de ejecucion: 01 -> 02 -> 03 -> 04. Los 4 archivos en ese orden equivalen al script integrado
docs/entrega2/Equipo03_Entrega2.sql (el mismo codigo, solo cortado por etapa).
**/


use FarmaciaBI;
go


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
