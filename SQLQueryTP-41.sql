/*
 Trabajo Práctico Integrador - Parte IV - 2025
 Nombre de los integrantes: BENKO, CURA, RIGANTI, SANJUAN
 Grupo: IV
 Fecha de entrega: 09/09/2025
*/

-- ===================================================================
-- Preparación del Entorno (Creación de esquemas y tablas auxiliares)
-- ===================================================================
-- Crear esquemas si no existen, para organizar los objetos de la BD
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'auditoria')
BEGIN
    EXEC('CREATE SCHEMA auditoria');
END
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'stage')
BEGIN
    EXEC('CREATE SCHEMA stage');
END
GO
-- Crear tabla para el Trigger de Auditoría
IF OBJECT_ID('auditoria.InscripcionesLog', 'U') IS NULL
BEGIN
    CREATE TABLE auditoria.InscripcionesLog (
        LogID INT IDENTITY(1,1) PRIMARY KEY,
        DniSocio INT,
        CodClase VARCHAR(10),
        NroSesion INT,
        UsuarioAccion NVARCHAR(128) DEFAULT SUSER_SNAME(),
        FechaAccion DATETIME DEFAULT GETDATE(),
        Accion NVARCHAR(50)
    );
END
GO
/*
 ====================================================================
 -- PUNTO 1: PROCEDIMIENTOS ALMACENADOS (STORED PROCEDURES)
 ====================================================================
*/

-- a) SP de consulta parametrizada
CREATE OR ALTER PROCEDURE usp_BuscarSociosPorLocalidad
    @Localidad NVARCHAR(50),
    @CantidadSocios INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        dni,
        nombre,
        apellido,
        email
    FROM
        personas.Socio
    WHERE
        localidad = @Localidad;

    -- Asignar el valor al parámetro de salida
    SELECT @CantidadSocios = @@ROWCOUNT;

    -- Mensaje informativo
    IF @CantidadSocios > 0
        PRINT 'Búsqueda exitosa. Se encontraron ' + CAST(@CantidadSocios AS VARCHAR) + ' socios.';
    ELSE
        PRINT 'No se encontraron socios en la localidad especificada.';
END
GO

-- b) SP de inserción de datos
CREATE OR ALTER PROCEDURE usp_RegistrarSocio
    @DNI INT,
    @Nombre NVARCHAR(50),
    @Apellido NVARCHAR(50),
    @FechaNacimiento DATE,
    @Email NVARCHAR(100),
    @Calle NVARCHAR(100),
    @Numero INT,
    @Localidad NVARCHAR(50) -- Sin coma aquí
AS
BEGIN
    SET NOCOUNT ON;

    -- Validaciones previas
    IF @DNI IS NULL OR @Nombre IS NULL OR @Apellido IS NULL OR @Email IS NULL
    BEGIN
        RAISERROR('El DNI, Nombre, Apellido y Email son campos obligatorios.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM personas.Socio WHERE dni = @DNI)
    BEGIN
        RAISERROR('El DNI ingresado ya se encuentra registrado.', 16, 1);
        RETURN;
    END

    -- Inserción del nuevo socio
    INSERT INTO personas.Socio (dni, nombre, apellido, fecha_nacimiento, email, calle, numero, localidad)
    VALUES (@DNI, @Nombre, @Apellido, @FechaNacimiento, @Email, @Calle, @Numero, @Localidad);

    PRINT 'Socio con DNI ' + CAST(@DNI AS VARCHAR) + ' registrado exitosamente.';
END
GO

    -- Validaciones previas
   EXEC usp_RegistrarSocio 
    @DNI = 40123456, 
    @Nombre = 'Martin', 
    @Apellido = 'Gomez', 
    @FechaNacimiento = '2000-01-01', 
    @Email = 'martin.g@email.com', 
    @Calle = 'Belgrano', 
    @Numero = 123, 
    @Localidad = 'Lomas del Mirador';
-- c) SP de eliminación controlada
CREATE OR ALTER PROCEDURE usp_EliminarClase
    @CodClase VARCHAR(10)
AS
BEGIN -- BEGIN del Procedimiento
    SET NOCOUNT ON;

    BEGIN TRY
        -- Verificar si la clase tiene sesiones asociadas (integridad referencial)
        IF EXISTS (SELECT 1 FROM actividades.Sesion WHERE cod_clase = @CodClase)
        BEGIN
            RAISERROR('No se puede eliminar la clase porque tiene sesiones programadas.', 16, 1);
            RETURN;
        END

        -- Si la verificación pasa, se intenta la eliminación
        DELETE FROM actividades.Clase
        WHERE cod_clase = @CodClase;

        IF @@ROWCOUNT > 0
            PRINT 'Clase ' + @CodClase + ' eliminada exitosamente.';
        ELSE
            PRINT 'La clase especificada no existe.';

    END TRY
    BEGIN CATCH
        -- Lógica a ejecutar SI OCURRE UN ERROR en el bloque TRY
        PRINT 'Ocurrió un error al intentar eliminar la clase: ' + ERROR_MESSAGE();
    END CATCH
    
END -- END del Procedimiento
GO
-- --- Ejemplos de ejecución de los SPs ---
PRINT '--- Ejecutando SP de Consulta ---';
DECLARE @count INT;
EXEC usp_BuscarSociosPorLocalidad @Localidad = 'Ramos Mejía', @CantidadSocios = @count OUTPUT;
SELECT @count AS 'Total Socios en Ramos Mejía';
GO

PRINT '--- Ejecutando SP de Inserción ---';
EXEC usp_RegistrarSocio @DNI = 40123456, @Nombre = 'Martin', @Apellido = 'Gomez', @FechaNacimiento = '2000-01-01', @Email = 'martin.g@email.com', @Calle = 'Belgrano', @Numero = 123, @Localidad = 'Lomas del Mirador';
GO

PRINT '--- Ejecutando SP de Eliminación (caso con error) ---';
EXEC usp_EliminarClase @CodClase = 'YOGA01'; -- Falla porque tiene sesiones
GO

/*
 ====================================================================
 -- PUNTO 2: TRIGGERS
 ====================================================================
*/

-- a) Trigger AFTER INSERT para auditoría
CREATE OR ALTER TRIGGER trg_AuditarNuevaInscripcion
ON gestion.Inscripcion
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO auditoria.InscripcionesLog (DniSocio, CodClase, NroSesion, Accion)
    SELECT
        i.dni_socio,
        i.cod_clase,
        i.nro_sesion,
        'Nueva Inscripción'
    FROM
        inserted i;
END
GO

-- b) Trigger INSTEAD OF UPDATE para validación
CREATE OR ALTER TRIGGER trg_PrevenirCambioEstadoInscripcion
ON gestion.Inscripcion
INSTEAD OF UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM deleted d
        JOIN inserted i ON d.dni_socio = i.dni_socio
                       AND d.cod_clase = i.cod_clase
                       AND d.nro_sesion = i.nro_sesion
        WHERE d.estado = 'Confirmada' AND i.estado <> 'Confirmada'
    )
    BEGIN
        RAISERROR('No se puede modificar el estado de una inscripción ya confirmada.', 16, 1);
    END
    ELSE
    BEGIN
        UPDATE i
        SET
            id_membresia = ins.id_membresia,
            fecha_inscripcion = ins.fecha_inscripcion,
            estado = ins.estado
        FROM
            gestion.Inscripcion i
        JOIN inserted ins ON i.dni_socio = ins.dni_socio
                          AND i.cod_clase = ins.cod_clase
                          AND i.nro_sesion = ins.nro_sesion;
    END
END
GO

/*
--====================================================================
-- (OPCIONAL) Bloque de pruebas para los SPs y Triggers
--====================================================================
*/

-- Prueba SP de Consulta
PRINT '--- Ejecutando SP de Consulta ---';
DECLARE @count INT;
EXEC usp_BuscarSociosPorLocalidad @Localidad = 'Ramos Mejía', @CantidadSocios = @count OUTPUT;
SELECT @count AS 'Total Socios en Ramos Mejía';
GO

-- Prueba SP de Inserción (usar un DNI nuevo para que no falle)
PRINT '--- Ejecutando SP de Inserción ---';
EXEC usp_RegistrarSocio @DNI = 49876543, @Nombre = 'Laura', @Apellido = 'Páez', @FechaNacimiento = '1999-05-20', @Email = 'laura.p@email.com', @Calle = 'Alsina', @Numero = 300, @Localidad = 'Ramos Mejía';
GO

-- Prueba SP de Eliminación (fallará porque la clase tiene sesiones, demostrando el control)
PRINT '--- Ejecutando SP de Eliminación (caso con error) ---';
EXEC usp_EliminarClase @CodClase = 'YOGA01';
GO

-- Prueba Trigger de Auditoría
PRINT '--- Probando Trigger de Auditoría ---';
INSERT INTO gestion.Inscripcion (dni_socio, cod_clase, nro_sesion, id_membresia, fecha_inscripcion, estado)
VALUES (34555666, 'YOGA01', 1, 'MEMB01', GETDATE(), 'Confirmada');
SELECT * FROM auditoria.InscripcionesLog WHERE Accion = 'Nueva Inscripción';
GO

-- Prueba Trigger de Validación (fallará, demostrando el control)
PRINT '--- Probando Trigger de Validación (INSTEAD OF) ---';
UPDATE gestion.Inscripcion
SET estado = 'Cancelada'
WHERE dni_socio = 30111222 AND cod_clase = 'YOGA01' AND nro_sesion = 1 AND estado = 'Confirmada';
GO

/*
 ====================================================================
 -- PUNTO 3: CURSOR DENTRO DE UN STORED PROCEDURE
 ====================================================================
*/

CREATE OR ALTER PROCEDURE usp_ProcesarSociosPorLocalidad_Cursor
    @Localidad NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Declarar variables para almacenar los datos de cada fila
    DECLARE @dni INT;
    DECLARE @nombre NVARCHAR(50);
    DECLARE @apellido NVARCHAR(50);
    DECLARE @fecha_nacimiento DATE;
    DECLARE @edad INT;

    -- 2. Declarar el cursor
    DECLARE socio_cursor CURSOR FOR
        SELECT dni, nombre, apellido, fecha_nacimiento
        FROM personas.Socio
        WHERE localidad = @Localidad;

    -- 3. Abrir el cursor
    OPEN socio_cursor;

    -- 4. Leer la primera fila
    FETCH NEXT FROM socio_cursor INTO @dni, @nombre, @apellido, @fecha_nacimiento;

    PRINT '--- Reporte de Edades para Socios de ' + @Localidad + ' ---';

    -- 5. Recorrer el cursor mientras haya filas
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Calcular la edad
        SET @edad = DATEDIFF(YEAR, @fecha_nacimiento, GETDATE());

        -- Mostrar el resultado por pantalla
        PRINT 'Socio: ' + @nombre + ' ' + @apellido + ' (DNI: ' + CAST(@dni AS VARCHAR) + ') - Edad: ' + CAST(@edad AS VARCHAR) + ' años.';

        -- Leer la siguiente fila
        FETCH NEXT FROM socio_cursor INTO @dni, @nombre, @apellido, @fecha_nacimiento;
    END

    -- 6. Cerrar el cursor
    CLOSE socio_cursor;

    -- 7. Liberar los recursos del cursor
    DEALLOCATE socio_cursor;
END
GO

-- --- Ejecución del SP con Cursor ---
EXEC usp_ProcesarSociosPorLocalidad_Cursor @Localidad = 'San Justo';
GO
//*
==============================================================
        PUNTO 4: Importación de JSON a SQL Server
        Archivo: barrios.json
==============================================================
*/

-- 1. Crear la tabla de destino para los barrios (si no existe)
IF OBJECT_ID('stage.Barrios', 'U') IS NULL
BEGIN
    CREATE TABLE stage.Barrios (
        ID_Barrio INT PRIMARY KEY,
        Nombre_Barrio NVARCHAR(100),
        Comuna INT
    );
END
GO

-- 2. Declarar la variable y cargar el JSON desde archivo
DECLARE @JSONData NVARCHAR(MAX);

-- Abrir el archivo JSON como texto
SELECT @JSONData = BulkColumn
FROM OPENROWSET(
        BULK 'C:\temp\barrios.json',  -- 📌 Ruta a tu archivo
        SINGLE_CLOB
    ) AS j;

-- 3. Insertar los datos del JSON en la tabla
INSERT INTO stage.Barrios (ID_Barrio, Nombre_Barrio, Comuna)
SELECT
    id,
    nombre,
    comuna
FROM OPENJSON(@JSONData, '$.features')
    WITH (
        id      INT             '$.properties.id',
        nombre  NVARCHAR(100)   '$.properties.nombre',
        comuna  INT             '$.properties.comuna'
    );

-- 4. Mostrar los registros insertados para verificar la importación
PRINT '--- Datos de barrios.json importados exitosamente ---';
SELECT * FROM stage.Barrios;
GO

/*
==============================================================
        Importación de CSV con corrección de caracteres
==============================================================
*/

DECLARE @CSVData NVARCHAR(MAX);

-- Abrir el archivo JSON como texto
SELECT @CSVData = BulkColumn
FROM OPENROWSET(
        BULK 'C:\temp\barrios_provincia.csv',  -- 📌 Ruta a tu archivo
        SINGLE_CLOB
    ) AS csv;

PRINT @CSVData;


-- 1. Crear la tabla de destino para los barrios (si no existe)
IF OBJECT_ID('dbo.BarriosProvincia', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.BarriosProvincia (
        ID_Barrio INT PRIMARY KEY,
        TipoObjeto VARCHAR(50),
        NombreBarrio NVARCHAR(100) -- Se usa NVARCHAR para soportar acentos
    );
END
GO
-- 2. Limpiar la tabla antes de una nueva carga (opcional)
TRUNCATE TABLE dbo.BarriosProvincia;
GO

-- 3. Importar el archivo CSV usando BULK INSERT
-- !! IMPORTANTE: Reemplaza la ruta con la ubicación de tu archivo !!
BULK INSERT dbo.BarriosProvincia
FROM 'C:\temp\barrios_provincia.csv'
WITH (
    FIRSTROW = 2,                -- Omitir la primera fila (el encabezado)
    FIELDTERMINATOR = ',',       -- El separador de columnas es la coma
    ROWTERMINATOR = '\n',        -- El separador de filas es el salto de línea
    CODEPAGE = '65001'           -- 📌 CORRECCIÓN: '65001' es para UTF-8, lo que arreglará los acentos
);
GO

-- 4. Verificar que los datos se importaron correctamente
PRINT '--- Datos importados a la tabla dbo.BarriosProvincia ---';
SELECT * FROM dbo.BarriosProvincia;
GO