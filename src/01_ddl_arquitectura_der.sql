/**
EQUIPO 3 - FarmaciaBI | Integracion de Datos | Universidad Iberoamericana Leon
01_ddl_arquitectura_der.sql - Base de datos y tablas DDL (modelo relacional)

Crea la base FarmaciaBI (la borra y la vuelve a crear) y las tablas del modelo: Pacientes y Medicamentos
(maestras), Ventas_Farmacia y Tickets_Atencion (transaccionales), con PK, FK y tipos de dato.
Cierre cualquier otra pestana de SSMS conectada a FarmaciaBI antes de ejecutarlo.

Orden de ejecucion: 01 -> 02 -> 03 -> 04. Los 4 archivos en ese orden equivalen al script integrado
docs/entrega2/Equipo03_Entrega2.sql (el mismo codigo, solo cortado por etapa).
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
