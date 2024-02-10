USE MASTER
GO

/************************************************************
 * Esta función devuelve 1 si existe el archivo indicado
 ************************************************************/

IF OBJECT_ID('fn_FileExists') IS NOT NULL
	DROP FUNCTION dbo.fn_FileExists
GO

CREATE FUNCTION dbo.fn_FileExists(@path varchar(512))
RETURNS BIT AS
BEGIN
     DECLARE @result INT
     EXEC master.dbo.xp_fileexist @path, @result OUTPUT
     RETURN cast(@result as bit)
END
GO