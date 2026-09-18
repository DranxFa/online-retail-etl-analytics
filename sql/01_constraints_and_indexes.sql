-- =========================================================================
-- PROYECTO: Online Retail Analytics (Data Mart Kimball)
-- SCRIPT: 01_constraints_and_indexes.sql
-- DESCRIPCIÓN: Estandariza tipos de datos (INT) y define Primary Keys,
--              Foreign Keys e Índices Clustered/NonClustered en OnlineRetailDW.
-- =========================================================================

USE OnlineRetailDW;
GO

-- 1. Estandarizar tipos y crear Llaves Primarias en Dimensiones (INT NOT NULL)
-- Dim_Geografia
ALTER TABLE dim_geografia ALTER COLUMN sk_geografia INT NOT NULL;
IF NOT EXISTS (SELECT * FROM sys.key_constraints WHERE name = 'PK_dim_geografia')
    ALTER TABLE dim_geografia ADD CONSTRAINT PK_dim_geografia PRIMARY KEY CLUSTERED (sk_geografia);

-- Dim_Cliente
ALTER TABLE dim_cliente ALTER COLUMN sk_cliente INT NOT NULL;
IF NOT EXISTS (SELECT * FROM sys.key_constraints WHERE name = 'PK_dim_cliente')
    ALTER TABLE dim_cliente ADD CONSTRAINT PK_dim_cliente PRIMARY KEY CLUSTERED (sk_cliente);

-- Dim_Producto
ALTER TABLE dim_producto ALTER COLUMN sk_producto INT NOT NULL;
IF NOT EXISTS (SELECT * FROM sys.key_constraints WHERE name = 'PK_dim_producto')
    ALTER TABLE dim_producto ADD CONSTRAINT PK_dim_producto PRIMARY KEY CLUSTERED (sk_producto);

-- Dim_Tiempo
ALTER TABLE dim_tiempo ALTER COLUMN sk_fecha INT NOT NULL;
IF NOT EXISTS (SELECT * FROM sys.key_constraints WHERE name = 'PK_dim_tiempo')
    ALTER TABLE dim_tiempo ADD CONSTRAINT PK_dim_tiempo PRIMARY KEY CLUSTERED (sk_fecha);
GO

-- 2. Estandarizar tipos en Fact_Ventas (convertir de BIGINT a INT para que coincidan con las dimensiones)
ALTER TABLE fact_ventas ALTER COLUMN id_venta INT NOT NULL;
ALTER TABLE fact_ventas ALTER COLUMN sk_cliente INT NOT NULL;
ALTER TABLE fact_ventas ALTER COLUMN sk_producto INT NOT NULL;
ALTER TABLE fact_ventas ALTER COLUMN sk_fecha INT NOT NULL;
ALTER TABLE fact_ventas ALTER COLUMN sk_geografia INT NOT NULL;

IF NOT EXISTS (SELECT * FROM sys.key_constraints WHERE name = 'PK_fact_ventas')
    ALTER TABLE fact_ventas ADD CONSTRAINT PK_fact_ventas PRIMARY KEY CLUSTERED (id_venta);
GO

-- 3. Crear Llaves Foráneas (Ahora que ambos lados son INT estrictos)
IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_ventas_cliente')
    ALTER TABLE fact_ventas ADD CONSTRAINT FK_ventas_cliente 
        FOREIGN KEY (sk_cliente) REFERENCES dim_cliente(sk_cliente);

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_ventas_producto')
    ALTER TABLE fact_ventas ADD CONSTRAINT FK_ventas_producto 
        FOREIGN KEY (sk_producto) REFERENCES dim_producto(sk_producto);

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_ventas_fecha')
    ALTER TABLE fact_ventas ADD CONSTRAINT FK_ventas_fecha 
        FOREIGN KEY (sk_fecha) REFERENCES dim_tiempo(sk_fecha);

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_ventas_geografia')
    ALTER TABLE fact_ventas ADD CONSTRAINT FK_ventas_geografia 
        FOREIGN KEY (sk_geografia) REFERENCES dim_geografia(sk_geografia);
GO

-- 4. Índices Non-Clustered en las Foreign Keys de Fact_Ventas (para acelerar JOINs)
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_fact_ventas_cliente' AND object_id = OBJECT_ID('fact_ventas'))
    CREATE NONCLUSTERED INDEX IX_fact_ventas_cliente ON fact_ventas(sk_cliente);

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_fact_ventas_fecha' AND object_id = OBJECT_ID('fact_ventas'))
    CREATE NONCLUSTERED INDEX IX_fact_ventas_fecha ON fact_ventas(sk_fecha);

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_fact_ventas_producto' AND object_id = OBJECT_ID('fact_ventas'))
    CREATE NONCLUSTERED INDEX IX_fact_ventas_producto ON fact_ventas(sk_producto);

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_fact_ventas_cancelacion' AND object_id = OBJECT_ID('fact_ventas'))
    CREATE NONCLUSTERED INDEX IX_fact_ventas_cancelacion ON fact_ventas(is_cancellation);
GO

PRINT '✅ Constraints e índices creados exitosamente en OnlineRetailDW.';
