/**
EQUIPO 3 - FarmaciaBI | Integracion de Datos | Universidad Iberoamericana Leon
03_etl_limpieza_plata.sql
Stored Procedures de limpieza y calidad: de bronce a plata

Procedimientos que leen bronce SIN modificarlo, limpian (trim, upper/lower, try_convert, coalesce), deduplican con
row_number, aplican las reglas de calidad y cargan plata. Son idempotentes: cada carga usa not exists, asi que
re-ejecutar el pipeline no duplica registros. Al final se valida y se compara bronce contra plata.

Roles: Daniel (procedimientos y corrida) y Bruno (validaciones).

Orden de ejecucion: 01 -> 02 -> 03 -> 04 (SQL Server 2019, SSMS). Cada archivo puede ejecutarse completo con F5.
**/
use FarmaciaBI;
go


/**
7. PROCEDIMIENTOS DE LIMPIEZA - DANIEL
Cada procedimiento carga una tabla de plata. Reglas comunes:
- Textos: trim quita espacios; upper / lower unifican mayusculas.
- Fechas, cantidades y montos: try_convert (si no se puede convertir queda null y el registro no pasa).
- Nulos: coalesce / el promedio de los valores disponibles.
- Duplicados: row_number() por llave; solo pasa la fila 1.
- Idempotencia: not exists contra la tabla destino.
create or alter procedure y go: SQL Server pide que el procedimiento vaya solo en su lote.
**/
create or alter procedure plata.sp_cargar_dim_medicamentos
as
begin
    set nocount on;

    with medicamentos_limpios as (
        select
            cast(trim(ean_medicamento) as varchar(13)) as ean_medicamento,
            coalesce(trim(nombre_comercial), 'Sin nombre') as nombre_comercial,
            coalesce(trim(sustancia_activa), 'Sin sustancia') as sustancia_activa,
            upper(trim(requiere_receta)) as requiere_receta,
            trim(estatus_alerta_sanitaria) as estatus_alerta_sanitaria,
            row_number() over (partition by trim(ean_medicamento) order by ean_medicamento) as numero_fila
        from bronce.stg_medicamentos
    )
    insert into plata.dim_medicamentos (
        ean_medicamento,
        nombre_comercial,
        sustancia_activa,
        requiere_receta,
        estatus_alerta_sanitaria
    )
    select
        m.ean_medicamento,
        m.nombre_comercial,
        m.sustancia_activa,
        m.requiere_receta,
        m.estatus_alerta_sanitaria
    from medicamentos_limpios m
    where m.numero_fila = 1
        and m.requiere_receta in ('SI', 'NO')
        and not exists (
            select 1
            from plata.dim_medicamentos d
            where d.ean_medicamento = m.ean_medicamento
        );
end;
go


/**
Pacientes: el dataset solo trae el ID de cliente dentro de las ventas, asi que se generan a partir de los IDs distintos.
**/
create or alter procedure plata.sp_cargar_dim_pacientes
as
begin
    set nocount on;

    with pacientes_unicos as (
        select distinct
            upper(trim(id_paciente)) as id_paciente
        from bronce.stg_ventas
        where trim(id_paciente) <> ''
    )
    insert into plata.dim_pacientes (
        id_paciente,
        nombre,
        apellido,
        correo
    )
    select
        p.id_paciente,
        'Paciente',
        replace(p.id_paciente, 'PAC-', ''),
        null
    from pacientes_unicos p
    where not exists (
        select 1
        from plata.dim_pacientes d
        where d.id_paciente = p.id_paciente
    );
end;
go


/**
Ventas: solo pasan las filas con fecha convertible, cantidad y monto mayores a cero, paciente y medicamento existentes
(integridad referencial) y que no esten ya cargadas.
**/
create or alter procedure plata.sp_cargar_fact_ventas
as
begin
    set nocount on;

    with ventas_limpias as (
        select
            upper(trim(id_venta)) as id_venta,
            try_convert(datetime, trim(fch_venta)) as fch_venta,
            upper(trim(id_paciente)) as id_paciente,
            cast(trim(ean_medicamento) as varchar(13)) as ean_medicamento,
            try_convert(int, trim(cantidad_piezas)) as cantidad_piezas,
            try_convert(decimal(10,2), trim(monto_total_mxn)) as mto_total_mxn,
            row_number() over (partition by upper(trim(id_venta)) order by id_venta) as numero_fila
        from bronce.stg_ventas
    )
    insert into plata.fact_ventas_farmacia (
        id_venta,
        fch_venta,
        id_paciente,
        ean_medicamento,
        cantidad_piezas,
        mto_total_mxn
    )
    select
        v.id_venta,
        v.fch_venta,
        v.id_paciente,
        v.ean_medicamento,
        v.cantidad_piezas,
        v.mto_total_mxn
    from ventas_limpias v
    where v.numero_fila = 1
        and v.fch_venta is not null
        and v.cantidad_piezas > 0
        and v.mto_total_mxn > 0
        and exists (
            select 1
            from plata.dim_pacientes p
            where p.id_paciente = v.id_paciente
        )
        and exists (
            select 1
            from plata.dim_medicamentos m
            where m.ean_medicamento = v.ean_medicamento
        )
        and not exists (
            select 1
            from plata.fact_ventas_farmacia f
            where f.id_venta = v.id_venta
        );
end;
go


/**
Tickets: se homologa el estatus (Cerrado / En Escalación), el tiempo nulo se imputa con el promedio de los tiempos
disponibles (coalesce) y solo pasan tickets cuya venta existe en plata.
**/
create or alter procedure plata.sp_cargar_fact_tickets
as
begin
    set nocount on;

    with tickets_limpios as (
        select
            upper(trim(id_ticket)) as id_ticket,
            upper(trim(id_venta)) as id_venta,
            trim(motivo_atencion) as motivo_atencion,
            case
                when lower(trim(estatus_ticket)) = 'cerrado' then 'Cerrado'
                when lower(trim(estatus_ticket)) in ('en escalacion', 'en escalación') then 'En Escalación'
                else trim(estatus_ticket)
            end as estatus_ticket,
            coalesce(tiempo_resolucion_min, (select avg(tiempo_resolucion_min) from bronce.stg_tickets where tiempo_resolucion_min is not null)) as tiempo_resolucion_min,
            row_number() over (partition by upper(trim(id_ticket)) order by id_ticket) as numero_fila
        from bronce.stg_tickets
    )
    insert into plata.fact_tickets_atencion (
        id_ticket,
        id_venta,
        motivo_atencion,
        estatus_ticket,
        tiempo_resolucion_min
    )
    select
        t.id_ticket,
        t.id_venta,
        t.motivo_atencion,
        t.estatus_ticket,
        t.tiempo_resolucion_min
    from tickets_limpios t
    where t.numero_fila = 1
        and t.estatus_ticket in ('Cerrado', 'En Escalación')
        and exists (
            select 1
            from plata.fact_ventas_farmacia v
            where v.id_venta = t.id_venta
        )
        and not exists (
            select 1
            from plata.fact_tickets_atencion f
            where f.id_ticket = t.id_ticket
        );
end;
go


/**
Linaje: registra en plata.aud_linaje_carga el recorrido de cada fuente. La bitacora guarda solo la ultima corrida
(truncate), por eso siempre tiene 7 pasos. Los conteos de plata se calculan con count(*) sobre las tablas reales.
En la ingesta el origen es el numero de filas que trae cada archivo o sistema.
**/
create or alter procedure plata.sp_registrar_linaje
as
begin
    set nocount on;

    truncate table plata.aud_linaje_carga;

    insert into plata.aud_linaje_carga (
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
    select 'Ingesta', 'Catálogo COFEPRIS', 'JSON', null, 'bronce.stg_medicamentos',
        'Carga cruda sin restricciones; el EAN se recibe como texto para no perder ceros a la izquierda',
        3, (select count(*) from bronce.stg_medicamentos), getdate(), 'Daniel'
    union all
    select 'Ingesta', 'Tickets de atención', 'CSV', null, 'bronce.stg_tickets',
        'Carga cruda sin restricciones para poder diagnosticar nulos, espacios y variantes de escritura',
        4, (select count(*) from bronce.stg_tickets), getdate(), 'Daniel'
    union all
    select 'Ingesta', 'BD operacional de ventas', 'SQL', null, 'bronce.stg_ventas',
        'Carga cruda; fecha, cantidad y monto llegan como texto',
        5, (select count(*) from bronce.stg_ventas), getdate(), 'Daniel'
    union all
    select 'Plata', 'Catálogo COFEPRIS', 'JSON', 'bronce.stg_medicamentos', 'plata.dim_medicamentos',
        'trim, upper en requiere_receta, cast del EAN a varchar(13), coalesce y deduplicacion por EAN con row_number',
        (select count(*) from bronce.stg_medicamentos), (select count(*) from plata.dim_medicamentos), getdate(), 'Daniel'
    union all
    select 'Plata', 'BD operacional de ventas', 'SQL', 'bronce.stg_ventas', 'plata.dim_pacientes',
        'Alta de pacientes a partir de los IDs de cliente distintos de las ventas (supuesto del equipo)',
        (select count(distinct upper(trim(id_paciente))) from bronce.stg_ventas), (select count(*) from plata.dim_pacientes), getdate(), 'Daniel'
    union all
    select 'Plata', 'BD operacional de ventas', 'SQL', 'bronce.stg_ventas', 'plata.fact_ventas_farmacia',
        'try_convert de fecha, cantidad y monto; cantidad y monto mayores a cero; paciente y medicamento existentes',
        (select count(*) from bronce.stg_ventas), (select count(*) from plata.fact_ventas_farmacia), getdate(), 'Daniel'
    union all
    select 'Plata', 'Tickets de atención', 'CSV', 'bronce.stg_tickets', 'plata.fact_tickets_atencion',
        'Homologacion de estatus, imputacion del tiempo nulo con el promedio y venta existente en plata',
        (select count(*) from bronce.stg_tickets), (select count(*) from plata.fact_tickets_atencion), getdate(), 'Daniel';
end;
go


/**
Orquestador: ejecuta todo el pipeline de bronce a plata en el orden que piden las llaves foraneas.
**/
create or alter procedure plata.sp_ejecutar_pipeline
as
begin
    set nocount on;

    exec plata.sp_cargar_dim_medicamentos;
    exec plata.sp_cargar_dim_pacientes;
    exec plata.sp_cargar_fact_ventas;
    exec plata.sp_cargar_fact_tickets;
    exec plata.sp_registrar_linaje;
end;
go


/**
Procedimientos de paciente - VALE
sp_insertar_paciente: limpia espacios (ltrim/rtrim), pasa el correo a minusculas (lower) y rechaza IDs repetidos (if exists / raiserror).
sp_consultar_paciente_por_id: devuelve los datos limpios; si no tiene correo muestra un valor por defecto (coalesce).
**/
create or alter procedure plata.sp_insertar_paciente
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
        from plata.dim_pacientes
        where id_paciente = @id_paciente
    )
    begin
        raiserror('El paciente ya existe en la base de datos.', 16, 1);
        return;
    end;

    insert into plata.dim_pacientes (id_paciente, nombre, apellido, correo)
    values (@id_paciente, @nombre, @apellido, @correo);
end;
go

create or alter procedure plata.sp_consultar_paciente_por_id
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
    from plata.dim_pacientes
    where id_paciente = @id_paciente;
end;
go


/**
8. CORRIDA DEL PIPELINE - DANIEL
Pregunta 8.1: Despues de la primera corrida, cuantos registros hay en bronce y cuantos pasaron a plata?
Pacientes se compara contra los IDs distintos porque plata guarda un registro por paciente.
R= medicamentos 3 y 3, pacientes 4 y 4, ventas 5 y 5, tickets 4 y 4. No se descarto ningun registro.
**/
exec plata.sp_ejecutar_pipeline;

select
    'medicamentos' as entidad,
    (select count(*) from bronce.stg_medicamentos) as filas_bronce,
    (select count(*) from plata.dim_medicamentos) as filas_plata
union all
select
    'pacientes (IDs distintos)',
    (select count(distinct id_paciente) from bronce.stg_ventas),
    (select count(*) from plata.dim_pacientes)
union all
select
    'ventas',
    (select count(*) from bronce.stg_ventas),
    (select count(*) from plata.fact_ventas_farmacia)
union all
select
    'tickets',
    (select count(*) from bronce.stg_tickets),
    (select count(*) from plata.fact_tickets_atencion);


/**
Pregunta 8.2: Que pasa si se ejecuta el pipeline otra vez (idempotencia)?
R= Los conteos de plata siguen igual: 3, 4, 5 y 4. Cada carga usa not exists, asi que no se duplica nada;
la bitacora de linaje sigue con 7 pasos porque guarda solo la ultima corrida.
**/
exec plata.sp_ejecutar_pipeline;

select
    (select count(*) from plata.dim_medicamentos) as dim_medicamentos,
    (select count(*) from plata.dim_pacientes) as dim_pacientes,
    (select count(*) from plata.fact_ventas_farmacia) as fact_ventas,
    (select count(*) from plata.fact_tickets_atencion) as fact_tickets,
    (select count(*) from plata.aud_linaje_carga) as pasos_linaje;


/**
Pregunta 8.3: Se puede volver a ingestar bronce y re-ejecutar todo sin duplicar?
Se vuelve a correr 02_etl_ingesta_bronce.sql (truncate + insert) y despues el pipeline.
R= Si. Bronce queda con 3, 4 y 5 filas y plata con los mismos conteos de la pregunta 8.2.
**/


/**
9. VALIDACIONES DE CALIDAD EN PLATA - BRUNO
Pregunta 9.1: Que restricciones CHECK protegen la capa plata?
R= 4 restricciones: receta SI/NO, cantidad mayor a cero, monto mayor a cero y estatus de ticket dentro del catalogo.
**/
select
    name as restriccion,
    definition as regla
from sys.check_constraints
order by name;


/**
Pregunta 9.2: Existe algun monto negativo? abs() muestra el valor corregido en caso de encontrarlo.
R= 0 registros. Todos los montos son positivos.
**/
select
    id_venta,
    mto_total_mxn,
    abs(mto_total_mxn) as Monto_Corregido
from plata.fact_ventas_farmacia
where mto_total_mxn < 0;


/**
Pregunta 9.3: Hay cantidades o montos en cero o negativos, o fechas fuera de agosto 2026?
R= 0 registros.
**/
select
    id_venta,
    fch_venta,
    cantidad_piezas,
    mto_total_mxn
from plata.fact_ventas_farmacia
where cantidad_piezas <= 0
    or mto_total_mxn <= 0
    or fch_venta < '20260801'
    or fch_venta >= '20260901';


/**
Pregunta 9.4: El precio por pieza de cada medicamento es el mismo en todas sus ventas?
R= Si. Tempra $90, Amoxil $450 y Bio-Grip $400; el minimo y el maximo coinciden.
**/
select
    m.nombre_comercial,
    min(v.mto_total_mxn / v.cantidad_piezas) as Precio_Minimo,
    max(v.mto_total_mxn / v.cantidad_piezas) as Precio_Maximo
from plata.fact_ventas_farmacia v
left join plata.dim_medicamentos m
    on v.ean_medicamento = m.ean_medicamento
group by m.nombre_comercial;


/**
Pregunta 9.5: Hay ventas cuyo EAN no exista en el catalogo (integracion con left join)?
R= 0 registros. Las 5 ventas encuentran su medicamento.
**/
select
    v.id_venta,
    v.ean_medicamento
from plata.fact_ventas_farmacia v
left join plata.dim_medicamentos m
    on v.ean_medicamento = m.ean_medicamento
where m.ean_medicamento is null;


/**
Pregunta 9.6: Que ventas no tienen ticket de atencion (integracion con left join)?
R= Solo FAR-904. Es normal: no toda venta genera una queja.
**/
select
    v.id_venta,
    t.id_ticket
from plata.fact_ventas_farmacia v
left join plata.fact_tickets_atencion t
    on v.id_venta = t.id_venta
where t.id_ticket is null;


/**
Pregunta 9.7: Despues de la limpieza, cuantos valores distintos quedan en el estatus?
R= Solo 2: "Cerrado" (3 tickets) y "En Escalación" (1 ticket), sin espacios.
**/
select
    '[' + estatus_ticket + ']' as Estatus_Visible,
    count(*) as Num_Tickets
from plata.fact_tickets_atencion
group by estatus_ticket;


/**
Pregunta 9.8: Quedan tiempos de resolucion nulos y que valor recibio TCK-303?
R= 0 nulos. TCK-303 quedo con 16 minutos (el promedio entero de 15, 25 y 10).
**/
select
    id_ticket,
    tiempo_resolucion_min
from plata.fact_tickets_atencion
where tiempo_resolucion_min is null
    or id_ticket = 'TCK-303';


/**
Pregunta 9.9: Cada tabla de plata tiene el numero de registros esperado?
R= Pacientes 4, Ventas 5, Medicamentos 3, Tickets 4. Ingreso total $2,820.
**/
select
    (select count(*) from plata.dim_pacientes) as Pacientes,
    (select count(*) from plata.fact_ventas_farmacia) as Ventas,
    (select count(*) from plata.dim_medicamentos) as Medicamentos,
    (select count(*) from plata.fact_tickets_atencion) as Tickets,
    (select sum(mto_total_mxn) from plata.fact_ventas_farmacia) as Ingreso_Total;


/**
Pregunta 9.10: Que recorrido siguieron los datos y se perdio algun registro en el camino?
R= 7 pasos: 3 de Ingesta (bronce) y 4 de Plata. En los 7 coinciden origen y destino: no se perdio ningun registro.
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
from plata.aud_linaje_carga
order by id_carga;
