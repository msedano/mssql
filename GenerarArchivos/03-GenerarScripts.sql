USE BaseDeDatos
GO

SET NOCOUNT ON
GO

/* -------------------------------------------------------------- */
/*                        PARAMETRIZACION                         */
/* -------------------------------------------------------------- */
DECLARE
	@DBName VARCHAR(255)         ='BaseDeDatos',  /* Nombre de la base de datos */
	@Path VARCHAR(MAX)           ='c:\tempdb\',   /* Path del server, NO local */
	@Sobreescribir TINYINT       =0,              /* Indicar 1 para sobreescribir los archivos generados */
	
	@li_GenerarSP INT            =1,              /* Indicar 1 para generar los archivos de procedimientos almacenados */
	@ls_FiltroSP VARCHAR(100)    ='%',            /* Indicar un filtro de procedimientos almacenados que se desean exportar */
	
	@li_GenerarFN INT            =1,              /* Indicar 1 para generar los archivos de funciones definidas por el usuario */
	@ls_FiltroFN VARCHAR(100)    ='%',            /* Indicar un filtro de funciones definidas por el usuario que se desean exportar */
	
	@li_GenerarVISTAS INT        =1,              /* Indicar 1 para generar los archivos de vistas */
	@ls_FiltroVISTAS VARCHAR(100)='%',            /* Indicar un filtro de vistas que se desean exportar */

	@li_GenerarTABLAS INT        =1,              /* Indicar 1 para generar los archivos de las tablas */
	@ls_FiltroTABLAS VARCHAR(100)='%'             /* Indicar un filtro de tablas que se desean exportar */

/* -------------------------------------------------------------- */
DECLARE
	@ObjectID INT,
	@STX NVARCHAR(MAX),
	@FileName VARCHAR(MAX),
	@CRLF CHAR(2)=CHAR(13)+CHAR(10)


IF (LTRIM(ISNULL(@DBName,''))<>'')
	SET @DBName='USE '+@DBName+@CRLF+
				'GO'+@CRLF+@CRLF
ELSE
	SET @DBName=''


/**************************************************************
GENERACIÓN DE SINTAXIS DE PROCEDIMIENTOS ALMACENADOS
***************************************************************/
IF @li_GenerarSP=1
BEGIN
	DECLARE lc_SPs CURSOR STATIC FOR
	SELECT object_id
	FROM sys.procedures
	WHERE is_ms_shipped=0 AND name like @ls_FiltroSP AND (CHARINDEX('diagram',name)=0)
	ORDER BY name
	
	OPEN lc_SPs
	FETCH lc_SPs INTO @ObjectID
	WHILE @@FETCH_STATUS=0
	BEGIN
		/* Sintaxis de eliminación */
		SELECT
			@STX=
				@DBName+
				'/* Procedimiento almacenado '+schema_name(schema_id)+'.'+name+' */'+@CRLF+@CRLF+
				'IF EXISTS (SELECT 1 FROM sys.procedures WHERE '+
				'object_id=OBJECT_ID(N'''+schema_name(schema_id)+'.'+replace(name,'''','''''')+'''))'+@CRLF+
				'	DROP PROCEDURE ['+schema_name(schema_id)+'].['+REPLACE(name,'''','''''')+']'+@CRLF+'GO'+@CRLF+@CRLF+
				'SET ANSI_NULLS ON'+@CRLF+
				'GO'+@CRLF+
				'SET QUOTED_IDENTIFIER ON'+@CRLF+
				'GO'+@CRLF+@CRLF,
			@FileName='sp - '+replace(name,'"','''')+'.sql'
		FROM sys.procedures
		WHERE object_id=@ObjectID
		
		/* Sintaxis de creación */
		SELECT
			@STX=@STX+
			definition+@CRLF+'GO'+@CRLF+@CRLF
		FROM sys.sql_modules
		WHERE object_id=@ObjectID
		
		IF EXISTS(
			SELECT 1
			FROM sys.database_permissions AS dp
			JOIN sys.objects AS o ON dp.major_id=o.object_id
			JOIN sys.schemas AS s ON o.schema_id = s.schema_id
			JOIN sys.database_principals AS dpr ON dp.grantee_principal_id=dpr.principal_id
		WHERE o.object_id=@ObjectID)
		SELECT @STX=@STX+
			'/* Asignación de permisos */'+@CRLF+@CRLF
		SELECT
			@STX=@STX+
			dp.state_desc + ' ' + dp.permission_name collate latin1_general_cs_as + 
			' ON ' + '[' + s.name + ']' + '.' + '[' + o.name + ']' +
			' TO ' + '[' + dpr.name + ']'+@CRLF+'GO'+@CRLF+@CRLF
		FROM sys.database_permissions AS dp
			JOIN sys.objects AS o ON dp.major_id=o.object_id
			JOIN sys.schemas AS s ON o.schema_id = s.schema_id
			JOIN sys.database_principals AS dpr ON dp.grantee_principal_id=dpr.principal_id
		WHERE o.object_id=@ObjectID
		ORDER BY dpr.name

		IF @Sobreescribir = 0 AND master.dbo.fn_FileExists(@Path+@FileName)=1
		BEGIN
			PRINT '               No se genera '+@FileName+' porque ya existe un archivo similar'
		END
		ELSE
		BEGIN
			PRINT 'Generando '+@FileName
			EXEC master.dbo.spWriteStringToFile
				@String=@STX,
				@Path=@Path,
				@Filename=@FileName
		END
		
		FETCH lc_SPs INTO @ObjectID
	END
	CLOSE lc_SPs
	DEALLOCATE lc_SPs
END


/********************************************************************
GENERACIÓN DE SINTAXIS DE FUNCIONES DEFINIDAS POR EL USUARIO
*********************************************************************/
IF @li_GenerarFN=1
BEGIN
	DECLARE lc_FNs CURSOR STATIC FOR
	SELECT object_id
	FROM sys.all_objects AS udf
	WHERE is_ms_shipped=0 AND name like @ls_FiltroFN AND udf.type in ('TF','FN','IF','FS','FT') AND (CHARINDEX('diagram',name)=0)
	ORDER BY name
	
	OPEN lc_FNs
	FETCH lc_FNs INTO @ObjectID
	WHILE @@FETCH_STATUS=0
	BEGIN
		/* Sintaxis de eliminación */
		SELECT
			@STX=
				@DBName+
				'/* Función definida por el usuario '+schema_name(schema_id)+'.'+name+' */'+@CRLF+@CRLF+
				'IF EXISTS (SELECT 1 FROM sys.all_objects WHERE '+
				'type in (''TF'',''FN'',''IF'',''FS'',''FT'') AND '+
				'object_id=OBJECT_ID(N'''+schema_name(schema_id)+'.'+replace(name,'''','''''')+'''))'+@CRLF+
				'	DROP FUNCTION ['+schema_name(schema_id)+'].['+REPLACE(name,'''','''''')+']'+@CRLF+'GO'+@CRLF+@CRLF,
			@FileName='fun - '+replace(name,'"','''')+'.sql'
		FROM sys.all_objects
		WHERE object_id=@ObjectID
	
		/* Sintaxis de creación */
		SELECT @STX=@STX+definition+@CRLF+'GO'+@CRLF+@CRLF
		FROM sys.sql_modules
		WHERE object_id=@ObjectID
	
		IF EXISTS(
			SELECT 1
			FROM sys.database_permissions AS dp
			JOIN sys.objects AS o ON dp.major_id=o.object_id
			JOIN sys.schemas AS s ON o.schema_id = s.schema_id
			JOIN sys.database_principals AS dpr ON dp.grantee_principal_id=dpr.principal_id
		WHERE o.object_id=@ObjectID)
		SELECT @STX=@STX+
			'/* Asignación de permisos */'+@CRLF+@CRLF
		SELECT
			@STX=@STX+
			dp.state_desc + ' ' + dp.permission_name collate latin1_general_cs_as + 
			' ON ' + '[' + s.name + ']' + '.' + '[' + o.name + ']' +
			' TO ' + '[' + dpr.name + ']'+@CRLF+'GO'+@CRLF+@CRLF
		FROM sys.database_permissions AS dp
			JOIN sys.objects AS o ON dp.major_id=o.object_id
			JOIN sys.schemas AS s ON o.schema_id = s.schema_id
			JOIN sys.database_principals AS dpr ON dp.grantee_principal_id=dpr.principal_id
		WHERE o.object_id=@ObjectID
		ORDER BY dpr.name

		IF @Sobreescribir = 0 AND master.dbo.fn_FileExists(@Path+@FileName)=1
		BEGIN
			PRINT '               No se genera '+@FileName+' porque ya existe un archivo similar'
		END
		ELSE
		BEGIN
			PRINT 'Generando '+@FileName
			EXEC master.dbo.spWriteStringToFile
				@String=@STX,
				@Path=@Path,
				@Filename=@FileName
		END
		
		FETCH lc_FNs INTO @ObjectID
	END
	CLOSE lc_FNs
	DEALLOCATE lc_FNs
END


/*************************************************
GENERACIÓN DE SINTAXIS DE VISTAS
*************************************************/
IF @li_GenerarVISTAS=1
BEGIN
	DECLARE lc_Vistas CURSOR STATIC FOR
	SELECT object_id
	FROM sys.views
	WHERE is_ms_shipped=0 AND name like @ls_FiltroVISTAS AND (CHARINDEX('diagram',name)=0)
	ORDER BY name
	
	OPEN lc_Vistas
	FETCH lc_Vistas INTO @ObjectID
	WHILE @@FETCH_STATUS=0
	BEGIN
		/* Sintaxis de eliminación */
		SELECT
			@STX=
				@DBName+
				'/* Vista '+schema_name(schema_id)+'.'+name+' */'+@CRLF+@CRLF+
				'IF EXISTS (SELECT 1 FROM sys.views WHERE '+
				'object_id=OBJECT_ID(N'''+schema_name(schema_id)+'.'+replace(name,'''','''''')+'''))'+@CRLF+
				'	DROP VIEW ['+schema_name(schema_id)+'].['+REPLACE(name,'''','''''')+']'+@CRLF+'GO'+@CRLF+@CRLF+
				'SET ANSI_NULLS ON'+@CRLF+
				'GO'+@CRLF+
				'SET QUOTED_IDENTIFIER ON'+@CRLF+
				'GO'+@CRLF+@CRLF,
			@FileName='vista - '+replace(name,'"','''')+'.sql'
		FROM sys.views WHERE object_id=@ObjectID
	
		/* Sintaxis de creación */
		SELECT @STX=@STX+definition+@CRLF+'GO'+@CRLF+@CRLF
		FROM sys.sql_modules
		WHERE object_id=@ObjectID
	
		IF EXISTS(
			SELECT 1
			FROM sys.database_permissions AS dp
			JOIN sys.objects AS o ON dp.major_id=o.object_id
			JOIN sys.schemas AS s ON o.schema_id = s.schema_id
			JOIN sys.database_principals AS dpr ON dp.grantee_principal_id=dpr.principal_id
		WHERE o.object_id=@ObjectID)
		SELECT @STX=@STX+
			'/* Asignación de permisos */'+@CRLF+@CRLF
		SELECT
			@STX=@STX+
			dp.state_desc + ' ' + dp.permission_name collate latin1_general_cs_as + 
			' ON ' + '[' + s.name + ']' + '.' + '[' + o.name + ']' +
			' TO ' + '[' + dpr.name + ']'+@CRLF+'GO'+@CRLF+@CRLF
		FROM sys.database_permissions AS dp
			JOIN sys.objects AS o ON dp.major_id=o.object_id
			JOIN sys.schemas AS s ON o.schema_id = s.schema_id
			JOIN sys.database_principals AS dpr ON dp.grantee_principal_id=dpr.principal_id
		WHERE o.object_id=@ObjectID
		ORDER BY dpr.name

		IF @Sobreescribir = 0 AND master.dbo.fn_FileExists(@Path+@FileName)=1
		BEGIN
			PRINT '               No se genera '+@FileName+' porque ya existe un archivo similar'
		END
		ELSE
		BEGIN
			PRINT 'Generando '+@FileName
			EXEC master.dbo.spWriteStringToFile
				@String=@STX,
				@Path=@Path,
				@Filename=@FileName
		END
		
		FETCH lc_Vistas INTO @ObjectID
	END
	CLOSE lc_Vistas
	DEALLOCATE lc_Vistas
END


/********************************************
     GENERACIÓN DE SINTAXIS DE TABLAS
********************************************/
IF @li_GenerarTABLAS=1
BEGIN
	DECLARE lc_Tablas CURSOR STATIC FOR
	SELECT object_id
	FROM sys.tables AS tbl
	WHERE is_ms_shipped=0 AND Name like @ls_FiltroTABLAS AND (CHARINDEX('diagram',name)=0)
	ORDER BY Name ASC
	
	/********************** SINTAXIS DE TABLAS **********************/
	OPEN lc_Tablas
	FETCH lc_Tablas INTO @ObjectID
	WHILE @@FETCH_STATUS=0
	BEGIN
		
		SET @STX=NULL
		
		/**********************
		SINTAXIS DE COLUMNAS
		**********************/
		SELECT
			@STX=ISNULL(@STX+','+@CRLF,'')+
			/* AQUI SE GENERA EL NOMBRE DE LA COLUMNA */
			'	['+c.name+'] '+
				
			/* SI NO ES COMPUTADA,SIGO ARMANDO LOS DATOS DE LA COLUMNA */
			CASE
				WHEN c.is_computed=0 THEN
						
					/* TIPO DE DATO */
					'['+t.name+']'+
						
					/* DE ACUERDO AL TIPO DE COLUMNA GENERO SINTAXIS DE TAMAÑO O DE TAMAÑO CON DECIMALES */
					CASE
						WHEN t.name IN ('varchar','char','nchar','nvarchar','varbinary') THEN 
							'('+CASE c.max_length WHEN -1 THEN 'MAX' ELSE LTRIM(STR(c.max_length)) END+')'
						WHEN t.name IN ('numeric','decimal')                             THEN
							'('+LTRIM(STR(c.precision))+','+LTRIM(STR(c.scale))+')'
						ELSE '' END+
						
					/* GENERO SINTAXIS DE IDENTITY */
					CASE
						WHEN c.is_identity=1 THEN ' IDENTITY (1,1)'
						WHEN c.is_identity=0 THEN ''
					END+
						
					/* GENERO SINTAXIS DE SI ES NULO */
					CASE
						WHEN c.is_nullable=1 THEN ' NULL'
						WHEN c.is_nullable=0 THEN ' NOT NULL'
					END+
						
					/* CONSTRAINT DE DEFAULT VALUE */
					CASE
						WHEN ISNULL(C.default_object_id,0) <> 0 THEN ' CONSTRAINT ['+OBJECT_NAME(C.default_object_id)+'] DEFAULT '+M.text
						ELSE ''
					END
						
				ELSE
					/* EXPRESION DE CAMPO COMPUTADO */
					'AS '+ISNULL(cc.definition,'///')
			END
			
		FROM dbo.sysobjects o WITH (nolock)
			JOIN sys.all_columns AS c ON c.object_id=o.id
			JOIN dbo.systypes t WITH (nolock) ON c.system_type_id=t.xtype and t.xusertype=c.user_type_id
			LEFT OUTER JOIN dbo.syscomments M WITH (nolock) ON M.id=C.default_object_id
			LEFT OUTER JOIN sys.computed_columns AS cc with (nolock) ON cc.object_id=c.object_id and cc.column_id=c.column_id
			LEFT OUTER JOIN sys.identity_columns AS ic ON ic.object_id=c.object_id and ic.column_id=c.column_id
		WHERE o.xtype in ('U','V')
		and o.id=@ObjectID
		ORDER BY c.column_id
			
		SELECT @STX=
			@DBName+
			'/* Tabla '+schema_name(schema_id)+'.'+name+' */'+@CRLF+@CRLF+
			'IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE '+
				'object_id=OBJECT_ID(N'''+schema_name(schema_id)+'.'+replace(name,'''','''''')+'''))'+@CRLF+
			'CREATE TABLE ['+schema_name(schema_id)+'].['+name+']('+@CRLF+@STX,
			@FileName='tabla - '+replace(name,'"','''')+'.sql'
		FROM sys.tables WHERE object_id=@ObjectID
			
		/************************
			SINTAXIS DE PRIMARY KEY
		*************************/
			
		IF EXISTS(SELECT 1 FROM sys.indexes AS i WHERE i.object_id=@ObjectID AND i.Is_Primary_Key=1)
		BEGIN
			SELECT
				@STX=@STX+','+@CRLF+
				'	CONSTRAINT ['+i.name+'] PRIMARY KEY '+i.type_desc+' ('
			FROM
				sys.indexes AS i
			WHERE
				i.object_id=@ObjectID AND
				i.Is_Primary_Key=1

			SELECT @STX=@STX+ISNULL(COL_NAME(object_id,column_id),'/* ERROR AL GENERAR EL NOMBRE DE CAMPO! */')+', '
			FROM sys.index_columns
			WHERE object_id=@ObjectID
			ORDER BY column_id
			SET @STX=LEFT(@STX,LEN(@STX)-2)+')'
		END
			
		/**********************
			PARENTESIS FINAL Y GO
		***********************/
		SET @STX=@STX+@CRLF+')'+@CRLF+
		'GO'+@CRLF+@CRLF

		/********************
		 SINTAXIS DE INDICES
		*********************/
		IF EXISTS(
			SELECT 1
			FROM sys.tables AS tbl
				JOIN sys.indexes AS i ON (i.index_id > 0 and i.is_hypothetical=0) AND (i.object_id=tbl.object_id)
			WHERE i.index_id > 1 AND tbl.object_id=@ObjectID)
		SELECT @STX=@STX+
			'/* Creación de índices */'+@CRLF+@CRLF
		SELECT @STX=@STX+
			CASE ic.index_column_id WHEN 1 THEN
			'IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE '+
			'object_id=OBJECT_ID(N'''+schema_name(schema_id)+'.'+replace(i.name,'''','''''')+''') AND name=N'''+i.name+''')'+@CRLF+
			'	CREATE '+(CASE i.is_unique WHEN 1 THEN 'UNIQUE ' ELSE '' END)+'NONCLUSTERED INDEX ['+i.name+'] ON '+
			schema_name(schema_id)+'.'+object_name(i.object_id)+'('+@CRLF
			ELSE '' END+
			
			'		['+ISNULL(clmns.name,'**************************')+']'+CASE ic.is_descending_key WHEN 0 THEN ' ASC' ELSE ' DESC' END+
			
			CASE WHEN ic.index_column_id=icm.index_column_max_id THEN
			@CRLF+'	)'+@CRLF+'GO'+@CRLF+@CRLF
			ELSE ','+@CRLF END
		FROM
			sys.tables AS tbl
			JOIN sys.indexes AS i ON (i.index_id > 0 and i.is_hypothetical=0) AND (i.object_id=tbl.object_id)
			JOIN sys.index_columns AS ic ON (ic.column_id > 0 and (ic.key_ordinal > 0 or ic.partition_ordinal=0))
			AND (ic.index_id=CAST(i.index_id AS int) AND ic.object_id=i.object_id)
			JOIN (
				SELECT
					ic.index_id,
					ic.object_id,
					index_column_max_id=MAX(ic.index_column_id)
				FROM
					sys.index_columns AS ic
				WHERE
					ic.column_id>0 AND ic.key_ordinal>0 AND ic.partition_ordinal=0
				GROUP BY
					ic.index_id,
					ic.object_id
			) AS icm ON (icm.index_id=CAST(i.index_id AS int) AND icm.object_id=i.object_id)
			JOIN sys.columns AS clmns ON clmns.object_id=ic.object_id and clmns.column_id=ic.column_id
		WHERE
			i.index_id > 1 AND tbl.object_id=@ObjectID
		ORDER BY
			i.name,(case ic.key_ordinal when 0 then cast(1 as tinyint) else ic.key_ordinal end)

		/********************
		 SINTAXIS DE FK
		*********************/
		IF EXISTS(
			SELECT 1
			FROM sys.foreign_keys fk
			join sys.tables fk_tab on fk_tab.object_id=fk.parent_object_id
		WHERE
			fk_tab.object_id=@ObjectID)
		SELECT @STX=@STX+
			'/* Creación de foreign keys */'+@CRLF+@CRLF
		SELECT @STX=@STX+
			'IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE name='''+fk.name+''')'+@CRLF+
			'	ALTER TABLE ['+schema_name(fk_tab.schema_id)+'].['+fk_tab.name+'] WITH CHECK ADD CONSTRAINT ['+fk.name+']'+@CRLF+
			'	FOREIGN KEY($$COLSFK['+fk.name+'])'+@CRLF+
			'	REFERENCES ['+schema_name(pk_tab.schema_id)+'].['+pk_tab.name+'] ($$COLSPK['+fk.name+'])'+@CRLF+'GO'+@CRLF+@CRLF
		FROM
			sys.foreign_keys fk
			join sys.tables fk_tab on fk_tab.object_id=fk.parent_object_id
			join sys.tables pk_tab on pk_tab.object_id=fk.referenced_object_id
		WHERE
			fk_tab.object_id=@ObjectID
		ORDER BY
			schema_name(fk_tab.schema_id) + '.' + fk_tab.name,
			schema_name(pk_tab.schema_id) + '.' + pk_tab.name

		SELECT @STX=
			REPLACE(
				REPLACE(
					@STX,
					'$$COLSFK['+fk.name+']', 
					
					'['+fk_col.name+']'+
					CASE WHEN fk_colsMax.constraint_column_id_max=fk_cols.constraint_column_id THEN '' 
					     ELSE ', $$COLSFK['+fk.name+']' END
				),
				'$$COLSPK['+fk.name+']', 
					
				'['+pk_col.name+']'+
				CASE WHEN fk_colsMax.constraint_column_id_max=fk_cols.constraint_column_id THEN '' ELSE ', $$COLSPK['+fk.name+']' END
			)
		FROM
			sys.foreign_keys fk
			join sys.tables fk_tab on fk_tab.object_id=fk.parent_object_id
			join sys.tables pk_tab on pk_tab.object_id=fk.referenced_object_id
			join sys.foreign_key_columns fk_cols on fk_cols.constraint_object_id=fk.object_id
			join (
				select
					fk_cols.constraint_object_id,
					constraint_column_id_max = max(fk_cols.constraint_column_id)
				from
					sys.foreign_key_columns fk_cols
				group by
					fk_cols.constraint_object_id
			) as fk_colsMax on fk_colsMax.constraint_object_id=fk.object_id
			join sys.columns fk_col on fk_col.column_id=fk_cols.parent_column_id and fk_col.object_id=fk_tab.object_id
			join sys.columns pk_col on pk_col.column_id=fk_cols.referenced_column_id and pk_col.object_id=pk_tab.object_id
		WHERE
			fk_tab.object_id=@ObjectID
		ORDER BY
			schema_name(fk_tab.schema_id) + '.' + fk_tab.name,
			schema_name(pk_tab.schema_id) + '.' + pk_tab.name, 
			fk_cols.constraint_column_id

		/**********************
		 SINTAXIS DE TRIGGER'S
		***********************/
		IF EXISTS(
			SELECT 1
			FROM sys.triggers tr
				JOIN sys.tables t ON t.object_id=tr.parent_id
			WHERE t.object_id=@ObjectID)
		SELECT @STX=@STX+
			'/* Creación de triggers */'+@CRLF+@CRLF
		SELECT @STX=@STX+
			'IF EXISTS (SELECT 1 FROM sys.triggers WHERE '+
			'object_id=OBJECT_ID(N'''+schema_name(t.schema_id)+'.'+replace(tr.name,'''','''''')+'''))'+@CRLF+
			'	DROP TRIGGER ['+tr.name+']'+@CRLF+
			'GO'+@CRLF+@CRLF+
			m.definition+@CRLF+'GO'+@CRLF+@CRLF
		FROM sys.sql_modules m
		JOIN sys.triggers tr ON m.object_id=tr.object_id
		JOIN sys.tables t ON t.object_id=tr.parent_id
		WHERE t.object_id=@ObjectID
		
		/************
		 COMENTARIOS
		*************/
		IF EXISTS(
			SELECT 1
			FROM sys.tables AS tbl
				JOIN sys.all_columns AS clmns ON clmns.object_id=tbl.object_id
				JOIN sys.extended_properties AS p ON p.major_id=clmns.object_id AND p.minor_id=clmns.column_id AND p.class=1
			WHERE tbl.object_id=@ObjectID)
		SELECT @STX=@STX+
			'/* Creación de comentarios */'+@CRLF+@CRLF
		SELECT @STX=@STX+
			'IF EXISTS(SELECT 1 FROM sys.extended_properties '+
				'where major_id=OBJECT_ID(N'''+schema_name(tbl.schema_id)+'.'+replace(tbl.name,'''','''''')+''') '+
				'and minor_id = (select column_id from sys.columns '+
					'where object_id=OBJECT_ID(N'''+schema_name(tbl.schema_id)+'.'+replace(tbl.name,'''','''''')+''') and '+
					'name = N'''+clmns.name+'''))'+@CRLF+
			'	EXEC sys.sp_dropextendedproperty @name=N'''+p.name+''',@level0type=N''SCHEMA'',@level0name=N'''+SCHEMA_NAME(tbl.schema_id)+
			''',@level1type=N''TABLE'',@level1name=N'''+tbl.name+''',@level2type=N''COLUMN'',@level2name=N'''+clmns.name+''''+@CRLF+
			'EXEC sys.sp_addextendedproperty @name=N'''+p.name+''',@value=N'''+REPLACE(CAST(p.value AS varchar(MAX)),'''','''''')+
			''',@level0type=N''SCHEMA'',@level0name=N'''+SCHEMA_NAME(tbl.schema_id)+
			''',@level1type=N''TABLE'',@level1name=N'''+tbl.name+''',@level2type=N''COLUMN'',@level2name=N'''+clmns.name+''''+@CRLF+
			'GO'+@CRLF+@CRLF
		FROM
			sys.tables AS tbl
			JOIN sys.all_columns AS clmns ON clmns.object_id=tbl.object_id
			JOIN sys.extended_properties AS p ON p.major_id=clmns.object_id AND p.minor_id=clmns.column_id AND p.class=1
		WHERE
			tbl.object_id=@ObjectID
		ORDER BY
			SCHEMA_NAME(tbl.schema_id) ASC,tbl.name ASC,clmns.column_id ASC,p.name ASC
	
		IF EXISTS(
			SELECT 1
			FROM sys.database_permissions AS dp
			JOIN sys.objects AS o ON dp.major_id=o.object_id
			JOIN sys.schemas AS s ON o.schema_id = s.schema_id
			JOIN sys.database_principals AS dpr ON dp.grantee_principal_id=dpr.principal_id
		WHERE o.object_id=@ObjectID)
		SELECT @STX=@STX+
			'/* Asignación de permisos */'+@CRLF+@CRLF
		SELECT
			@STX=@STX+
			dp.state_desc + ' ' + dp.permission_name collate latin1_general_cs_as + 
			' ON ' + '[' + s.name + ']' + '.' + '[' + o.name + ']' +
			' TO ' + '[' + dpr.name + ']'+@CRLF+'GO'+@CRLF+@CRLF
		FROM sys.database_permissions AS dp
			JOIN sys.objects AS o ON dp.major_id=o.object_id
			JOIN sys.schemas AS s ON o.schema_id = s.schema_id
			JOIN sys.database_principals AS dpr ON dp.grantee_principal_id=dpr.principal_id
		WHERE o.object_id=@ObjectID
		ORDER BY dpr.name

		IF @Sobreescribir = 0 AND master.dbo.fn_FileExists(@Path+@FileName)=1
		BEGIN
			PRINT '               No se genera '+@FileName+' porque ya existe un archivo similar'
		END
		ELSE
		BEGIN
			PRINT 'Generando '+@FileName
			EXEC master.dbo.spWriteStringToFile
				@String=@STX,
				@Path=@Path,
				@Filename=@FileName
		END
		
		FETCH lc_Tablas INTO @ObjectID
	END
	CLOSE lc_Tablas
	DEALLOCATE lc_Tablas
END

