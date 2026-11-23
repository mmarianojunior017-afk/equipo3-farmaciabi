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
