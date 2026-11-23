/**
EQUIPO 3 - FarmaciaBI | Integracion de Datos | Universidad Iberoamericana Leon
02_etl_ingesta_bronce.sql - Ingesta cruda a staging (capa bronce) y diagnostico

Crea las tablas staging_medicamentos (JSON COFEPRIS) y staging_tickets (CSV) sin restricciones, carga los
datos tal como llegan y ejecuta el diagnostico de calidad sobre lo crudo (nulos, espacios, variantes, EAN, duplicados).

Orden de ejecucion: 01 -> 02 -> 03 -> 04. Los 4 archivos en ese orden equivalen al script integrado
docs/entrega2/Equipo03_Entrega2.sql (el mismo codigo, solo cortado por etapa).
**/


use FarmaciaBI;
go


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
