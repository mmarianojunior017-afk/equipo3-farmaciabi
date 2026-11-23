/**
EQUIPO 3 - FarmaciaBI | Integracion de Datos | Universidad Iberoamericana Leon
02_etl_ingesta_bronce.sql
Ingesta cruda a bronce y diagnostico de datos

Carga las tres fuentes a la capa bronce sin modificarlas y mide las anomalias que traen antes de limpiarlas.
La carga es re-ejecutable: cada corrida vacia las tablas de bronce con truncate y vuelve a insertar.

Roles: Daniel (ingesta) y Bruno (diagnostico).

Orden de ejecucion: 01 -> 02 -> 03 -> 04 (SQL Server 2019, SSMS). Cada archivo puede ejecutarse completo con F5.
**/
use FarmaciaBI;
go


/**
5. INGESTA A BRONCE - DANIEL
Fuentes: catalogo COFEPRIS (JSON), tickets de atencion (CSV) y ventas de la base operacional (SQL).
Se usa insert porque los datos del proyecto son una muestra pequena; con archivos reales aqui iria bulk insert.
truncate table deja la ingesta lista para re-ejecutarse sin duplicar registros.
**/
truncate table bronce.stg_medicamentos;
truncate table bronce.stg_tickets;
truncate table bronce.stg_ventas;

insert into bronce.stg_medicamentos (
    ean_medicamento,
    nombre_comercial,
    sustancia_activa,
    requiere_receta,
    estatus_alerta_sanitaria
)
values
('7501000001010', 'Tempra Forte 650mg', 'Paracetamol', 'NO', 'Vigente'),
('7501000002020', 'Amoxil 500mg', 'Amoxicilina', 'SI', 'Vigente'),
('7501000003030', 'Bio-Grip Restructurado', 'Antihistamínico Compuesto', 'NO', 'Bajo Revisión');

insert into bronce.stg_tickets (
    id_ticket,
    id_venta,
    motivo_atencion,
    estatus_ticket,
    tiempo_resolucion_min
)
values
('TCK-301', 'FAR-901', 'Cobro Incorrecto', ' Cerrado ', 15),
('TCK-302', 'FAR-902', 'Surtido Incompleto', 'CERRADO', 25),
('TCK-303', 'FAR-903', 'Efecto Secundario Reportado', ' En Escalacion ', null),
('TCK-304', 'FAR-905', 'Duda de Posología', 'Cerrado', 10);

/**
Las fechas van en formato yyyymmdd: SQL Server las lee igual en cualquier idioma. Con un login en espanol,
'2026-08-01' en una columna datetime se leeria como 8 de enero y el historial de agosto saldria vacio.
**/
insert into bronce.stg_ventas (
    id_venta,
    fch_venta,
    id_paciente,
    ean_medicamento,
    cantidad_piezas,
    monto_total_mxn
)
values
('FAR-901', '20260801 08:30:00', 'PAC-101', '7501000001010', '2', '180.00'),
('FAR-902', '20260801 10:15:00', 'PAC-102', '7501000002020', '1', '450.00'),
('FAR-903', '20260802 13:40:00', 'PAC-103', '7501000003030', '3', '1200.00'),
('FAR-904', '20260802 17:00:00', 'PAC-101', '7501000001010', '1', '90.00'),
('FAR-905', '20260803 19:20:00', 'PAC-104', '7501000002020', '2', '900.00');


/**
6. DIAGNOSTICO DE BRONCE - BRUNO
Pregunta 6.1: Cuantas filas llegaron a cada tabla de bronce?
R= stg_medicamentos 3, stg_tickets 4 y stg_ventas 5.
**/
select
    'stg_medicamentos' as tabla_bronce,
    count(*) as filas
from bronce.stg_medicamentos
union all
select
    'stg_tickets',
    count(*)
from bronce.stg_tickets
union all
select
    'stg_ventas',
    count(*)
from bronce.stg_ventas;


/**
Pregunta 6.2: Cuantos valores nulos tiene cada columna de los tickets crudos?
R= Solo tiempo_resolucion_min tiene 1 nulo (TCK-303).
**/
select
    count(*) as Total_Registros,
    sum(case when id_ticket is null then 1 else 0 end) as Nulos_ID_Ticket,
    sum(case when id_venta is null then 1 else 0 end) as Nulos_ID_Venta,
    sum(case when motivo_atencion is null then 1 else 0 end) as Nulos_Motivo,
    sum(case when estatus_ticket is null then 1 else 0 end) as Nulos_Estatus,
    sum(case when tiempo_resolucion_min is null then 1 else 0 end) as Nulos_Tiempo
from bronce.stg_tickets;


/**
Pregunta 6.3: Que tickets tienen espacios extra al inicio o al final del estatus?
Se usa datalength porque SQL Server ignora los espacios finales al comparar con =.
R= 2 tickets: TCK-301 (" Cerrado ") y TCK-303 (" En Escalacion ").
**/
select
    id_ticket,
    '[' + estatus_ticket + ']' as Estatus_Visible,
    datalength(estatus_ticket) as Largo_Original,
    datalength(ltrim(rtrim(estatus_ticket))) as Largo_Sin_Espacios
from bronce.stg_tickets
where datalength(estatus_ticket) <> datalength(ltrim(rtrim(estatus_ticket)));


/**
Pregunta 6.4: De cuantas formas distintas esta escrito el mismo estatus?
R= "Cerrado" aparece de 3 formas: "Cerrado", " Cerrado " y "CERRADO". "En Escalacion" viene sin acento y con espacios.
**/
select
    id_ticket,
    '[' + estatus_ticket + ']' as Estatus_Visible
from bronce.stg_tickets
order by id_ticket;


/**
Pregunta 6.5: Todos los EAN del catalogo tienen 13 caracteres (sin perdida de ceros a la izquierda)?
R= 0 registros. Los 3 EAN tienen 13 caracteres.
**/
select
    ean_medicamento,
    len(ean_medicamento) as Largo_EAN
from bronce.stg_medicamentos
where len(ean_medicamento) <> 13;


/**
Pregunta 6.6: Hay registros repetidos por reintentos de ingesta en alguna tabla de bronce?
R= 0 registros en las tres consultas.
**/
select
    id_ticket,
    count(*) as Veces
from bronce.stg_tickets
group by id_ticket
having count(*) > 1;

select
    ean_medicamento,
    count(*) as Veces
from bronce.stg_medicamentos
group by ean_medicamento
having count(*) > 1;

select
    id_venta,
    count(*) as Veces
from bronce.stg_ventas
group by id_venta
having count(*) > 1;


/**
Pregunta 6.7: Hay ventas con fecha que no se puede convertir, o con cantidad o monto en cero o negativos?
try_convert regresa null cuando el texto no se puede convertir, en lugar de marcar error.
R= 0 registros. Las 5 ventas se convierten sin problema y todas son positivas.
**/
select
    id_venta,
    fch_venta,
    cantidad_piezas,
    monto_total_mxn
from bronce.stg_ventas
where try_convert(datetime, trim(fch_venta)) is null
    or try_convert(int, trim(cantidad_piezas)) is null
    or try_convert(int, trim(cantidad_piezas)) <= 0
    or try_convert(decimal(10,2), trim(monto_total_mxn)) is null
    or try_convert(decimal(10,2), trim(monto_total_mxn)) <= 0;


/**
Pregunta 6.8: Hay registros huerfanos: tickets sin venta o ventas sin medicamento en el catalogo?
R= 0 registros en ambas consultas.
**/
select
    t.id_ticket,
    t.id_venta
from bronce.stg_tickets t
left join bronce.stg_ventas v
    on trim(t.id_venta) = trim(v.id_venta)
where v.id_venta is null;

select
    v.id_venta,
    v.ean_medicamento
from bronce.stg_ventas v
left join bronce.stg_medicamentos m
    on trim(v.ean_medicamento) = trim(m.ean_medicamento)
where m.ean_medicamento is null;


/**
Pregunta 6.9: Cual es el resumen de anomalias detectadas en bronce?
R= 1 tiempo de resolucion nulo, 2 estatus con espacios extra, 0 ventas invalidas y 0 huerfanos.
**/
select
    'tiempo_resolucion_min nulo' as anomalia,
    count(*) as registros
from bronce.stg_tickets
where tiempo_resolucion_min is null
union all
select
    'estatus con espacios extra',
    count(*)
from bronce.stg_tickets
where datalength(estatus_ticket) <> datalength(ltrim(rtrim(estatus_ticket)))
union all
select
    'ventas con fecha, cantidad o monto invalidos',
    count(*)
from bronce.stg_ventas
where try_convert(datetime, trim(fch_venta)) is null
    or try_convert(int, trim(cantidad_piezas)) is null
    or try_convert(int, trim(cantidad_piezas)) <= 0
    or try_convert(decimal(10,2), trim(monto_total_mxn)) is null
    or try_convert(decimal(10,2), trim(monto_total_mxn)) <= 0
union all
select
    'tickets huerfanos (venta inexistente)',
    count(*)
from bronce.stg_tickets t
left join bronce.stg_ventas v
    on trim(t.id_venta) = trim(v.id_venta)
where v.id_venta is null
union all
select
    'ventas huerfanas (medicamento inexistente)',
    count(*)
from bronce.stg_ventas v
left join bronce.stg_medicamentos m
    on trim(v.ean_medicamento) = trim(m.ean_medicamento)
where m.ean_medicamento is null;
