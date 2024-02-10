USE MASTER
GO

/***********************************************************************************************
 * Genera un archivo con el contenido de @String, en la carpeta @Path, en el archivo @Filename
 ***********************************************************************************************/

IF OBJECT_ID('spWriteStringToFile') IS NOT NULL
	DROP PROCEDURE spWriteStringToFile
GO

CREATE PROCEDURE spWriteStringToFile
	@String   NVARCHAR(MAX), --8000 in SQL Server 2000
	@Path     VARCHAR(255), 
	@Filename VARCHAR(255)
AS
DECLARE
	@objFileSystem   INT=NULL, 
	@objTextStream   INT=NULL, 
	@objErrorObject  INT, 
	@strErrorMessage VARCHAR(MAX), 
	@Command         VARCHAR(MAX), 
	@hr              INT, 
	@fileAndPath     VARCHAR(255)

SET NOCOUNT ON

SELECT @strErrorMessage='opening the File System Object'

EXECUTE @hr=sp_OACreate 'Scripting.FileSystemObject', @objFileSystem OUT

IF RIGHT(@path, 1)='\'
	SET @FileAndPath=@path+@filename
ELSE
	SET @FileAndPath=@path+'\'+@filename
IF @hr=0 SELECT @objErrorObject=@objFileSystem, @strErrorMessage='Creating file "'+@FileAndPath+'"'
IF @hr=0 EXECUTE @hr=sp_OAMethod @objFileSystem, 'CreateTextFile', @objTextStream OUT, @FileAndPath, 2, False

IF @hr=0 SELECT @objErrorObject=@objTextStream, @strErrorMessage='writing to the file "'+@FileAndPath+'"'
IF @hr=0 EXECUTE @hr=sp_OAMethod @objTextStream, 'Write', NULL, @String

IF @hr=0 SELECT @objErrorObject=@objTextStream, @strErrorMessage='closing the file "'+@FileAndPath+'"'
IF @hr=0 EXECUTE @hr=sp_OAMethod @objTextStream, 'Close'

IF @hr<>0
BEGIN
	DECLARE 
		@Source varchar(255), 
		@Description Varchar(255), 
		@Helpfile Varchar(255), 
		@HelpID int
	
	EXECUTE sp_OAGetErrorInfo @objErrorObject, @source output, @Description output, @Helpfile output, @HelpID output
	SELECT @strErrorMessage='Error whilst '+ISNULL(@strErrorMessage, 'doing something')+', '+ISNULL(@Description, '')
	RAISERROR (@strErrorMessage, 16, 1)
END
IF @objTextStream IS NOT NULL EXECUTE sp_OADestroy @objTextStream
IF @objFileSystem IS NOT NULL EXECUTE sp_OADestroy @objFileSystem
GO
