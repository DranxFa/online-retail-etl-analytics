import os
from pathlib import Path
from sqlalchemy import create_engine, event

import pandas as pd
import urllib
import time
import pyodbc

# Cargar variables de entorno desde .env
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    env_file = Path('.env')
    if env_file.exists():
        with open(env_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    os.environ.setdefault(k.strip(), v.strip().strip("'\""))


RAW_DATA_PATH = Path('online_retail_II.xlsx')
PROCESSED_DATA_PATH = Path('data_raw_consolidated.parquet')

def load_and_cache_raw_data() -> pd.DataFrame:
    
    if PROCESSED_DATA_PATH.exists():
        print('Cargando datos desde archivo Parquet')
        return pd.read_parquet(PROCESSED_DATA_PATH)

    print('Leyendo datos desde Excel')
    start = time.time()

    df_2009 = pd.read_excel(RAW_DATA_PATH, sheet_name= 'Year 2009-2010')
    df_2010 = pd.read_excel(RAW_DATA_PATH, sheet_name= 'Year 2010-2011')

    df_total = pd.concat([df_2009, df_2010], ignore_index= True)

    df_total['Invoice'] = df_total['Invoice'].astype(str)
    df_total['StockCode'] = df_total['StockCode'].astype(str)
    df_total['Country'] = df_total['Country'].astype(str)
    df_total['Description'] = df_total['Description'].astype(str)

    df_total.to_parquet(PROCESSED_DATA_PATH, index= False)
    print(f'Datos consolidados y guardados en Parquet en {time.time() - start:.1f}s')
    print(f'Total filas: {len(df_total):,}')

    return df_total

def audit_raw_data(df: pd.DataFrame) -> None:

    total_rows = len(df)
    print('\n' + '=' * 55)
    print("REPORTE DE AUDITORÍA DE CALIDAD DE DATOS")
    print("=" * 55)
    print(f'Total registros cargados: {total_rows:,}\n')

    duplicates = df.duplicated().sum()
    print(f'Duplicados exactos: {duplicates:,} ({duplicates / total_rows * 100:.2f}%)\n')

    print('\n Valores Nulos por Columna')
    nulls = df.isnull().sum()
    for col, val in nulls.items():
        if val > 0:
            print(f' - {col}: {val:,} nulos ({val / total_rows * 100:.2f}%)')

    cancellations = df['Invoice'].str.startswith('C', na= False).sum()
    print(f"\n Facturas con prefijo 'C' (Cancelaciones) {cancellations:,} ({cancellations/total_rows * 100:.2f}%)")

    negative_qty = (df['Quantity'] < 0).sum()
    print(f'Registros con Cantidad < 0 {negative_qty:,} ({negative_qty / total_rows * 100:.2f}%)')

    zero_or_neg_price  = (df['Price'] <= 0).sum()
    print(f'Registros con Precio <= 0 {zero_or_neg_price} ({zero_or_neg_price / total_rows * 100:.2f}%)')
    print('=' * 55 + '\n')



def clean_and_transform(df: pd.DataFrame) -> pd.DataFrame:
    
    print('\n Iniciando proceso de transformación y limpieza..')
    initial_rows = len(df)

    df_clean = df.rename(columns={
        'Invoice': 'invoice_no',
        'StockCode': 'stock_code',
        'Description': 'description',
        'Quantity': 'quantity',
        'InvoiceDate': 'invoice_date',
        'Price': 'unit_price',
        'Customer ID': 'customer_id',
        'Country': 'country',
    }).copy()

    df_clean = df_clean.drop_duplicates()
    print(f'Filas tras eliminar duplicados: {len(df_clean):,}')

    df_clean = df_clean[df_clean['customer_id'].notnull()].copy()
    df_clean['customer_id'] = df_clean['customer_id'].astype(int)
    print(f'Filas con Customer ID válido: {len(df_clean):,}')

    df_clean = df_clean[df_clean['unit_price'] > 0 ].copy()
    print(f'Filas con Unit Price > 0: {len(df_clean):,}')

    df_clean['is_cancellation'] = (df_clean['invoice_no'].str.startswith('C') | (df_clean['quantity'] < 0))

    df_clean['invoice_date'] = pd.to_datetime(df_clean['invoice_date'])
    df_clean['total_amount'] = (df_clean['quantity'] * df_clean['unit_price']).round(2)

    final_rows = len(df_clean)
    retention_pct = (final_rows / initial_rows) * 100
    print(f'Limpieza finalizada: {final_rows:,} registros listos ({retention_pct:.1f}% de retención)\n')

    return df_clean


def build_dimensional_model(df_clean: pd.DataFrame) -> dict:

    print('Construyendo el modelo dimensional (Esquema Estrella)...')

    dim_geografia = df_clean[['country']].drop_duplicates().reset_index(drop=True)
    dim_geografia['sk_geografia'] = dim_geografia.index + 1
    dim_geografia = dim_geografia[['sk_geografia', 'country']]
    
    dim_cliente = df_clean[['customer_id', 'country']].drop_duplicates(subset=['customer_id']).reset_index(drop=True)
    dim_cliente['sk_cliente'] = dim_cliente.index + 1
    dim_cliente = dim_cliente[['sk_cliente', 'customer_id', 'country']]

    dim_producto = df_clean.groupby('stock_code')['description'].last().reset_index()
    dim_producto['sk_producto'] = dim_producto.index + 1
    dim_producto = dim_producto[['sk_producto', 'stock_code', 'description']]

    min_date = df_clean['invoice_date'].min().date()
    max_date = df_clean['invoice_date'].max().date()
    date_range = pd.date_range(min_date, max_date)

    dim_tiempo = pd.DataFrame({'fecha': date_range})
    dim_tiempo['sk_fecha'] = dim_tiempo['fecha'].dt.strftime('%Y%m%d').astype(int)
    dim_tiempo['year'] = dim_tiempo['fecha'].dt.year
    dim_tiempo['quarter'] = dim_tiempo['fecha'].dt.quarter
    dim_tiempo['month_number'] = dim_tiempo['fecha'].dt.month
    dim_tiempo['month_name'] = dim_tiempo['fecha'].dt.strftime('%B')
    dim_tiempo['day_of_week'] =  dim_tiempo['fecha'].dt.strftime('%A')

    fact_ventas = df_clean.copy()

    fact_ventas['sk_fecha'] = fact_ventas['invoice_date'].dt.strftime('%Y%m%d').astype(int)

    fact_ventas = fact_ventas.merge(dim_geografia, on='country', how='left')
    fact_ventas = fact_ventas.merge(dim_cliente[['customer_id', 'sk_cliente']], on='customer_id', how='left')
    fact_ventas = fact_ventas.merge(dim_producto[['stock_code', 'sk_producto']], on='stock_code', how='left')

    fact_ventas['id_venta'] = fact_ventas.reset_index().index + 1

    fact_ventas = fact_ventas[[
        'id_venta',
        'sk_cliente',
        'sk_producto',
        'sk_fecha',
        'sk_geografia',
        'invoice_no',
        'quantity',
        'unit_price',
        'total_amount',
        'is_cancellation'
    ]]

    print('Tablas dimensionales creadas con éxito:')

    print(f' - Dim_Geografia: {len(dim_geografia):,} filas')
    print(f' - Dim_Cliente: {len(dim_cliente):,} filas')
    print(f' - Dim_Producto: {len(dim_producto):,} filas')
    print(f' - Dim_Tiempo: {len(dim_tiempo):,} filas')
    print(f' - Dim_Ventas: {len(fact_ventas):,} filas\n')

    return{
        'dim_geografia': dim_geografia,
        'dim_cliente': dim_cliente,
        'dim_producto': dim_producto,
        'dim_tiempo': dim_tiempo,
        'fact_ventas': fact_ventas,
    }

def load_to_sql_server(
    tables: dict, 
    server_name: str = None, 
    db_name: str = None, 
    db_user: str = None, 
    db_password: str = None
) -> None:
    server_name = server_name or os.getenv('DB_SERVER', 'localhost')
    db_name = db_name or os.getenv('DB_NAME', 'OnlineRetailDW')
    db_user = db_user or os.getenv('DB_USER', 'sa')
    db_password = db_password or os.getenv('DB_PASSWORD', '')

    print(f'Conectando a SQL Server ({server_name}) en la BD "{db_name}..."')

    available_drivers = [d for d in pyodbc.drivers() if 'SQL Server' in d]

    if not available_drivers:
        raise RuntimeError('No se encontró ningún driver ODBC de SQL Server instalado en tu sistema')
    
    driver = 'ODBC Driver 17 for SQL Server'
    if 'ODBC Driver 18 for SQL Server' in available_drivers:
        driver = 'ODBC Driver 18 for SQL Server'
    elif driver not in available_drivers:
        driver = available_drivers[0]

    print(f'Usando driver: {driver}\n')

    connection_string = (
        f"DRIVER={{{driver}}};"
        f"SERVER={server_name};"
        f"DATABASE={db_name};"
        f"UID={db_user};"
        f"PWD={db_password};"
        f"TrustServerCertificate=yes;"
    )

    params = urllib.parse.quote_plus(connection_string)
    engine = create_engine(f'mssql+pyodbc:///?odbc_connect={params}')

    
    @event.listens_for(engine, 'before_cursor_execute')
    def receive_before_cursor_execute(conn, cursor, statement, params, context, executemany):

        if executemany:
            cursor.fast_executemany = True

    dimensiones = ['dim_geografia', 'dim_cliente', 'dim_producto', 'dim_tiempo']

    for dim in dimensiones:
        print(f'Insertando {dim} ({len(tables[dim]):,} filas...)')
        tables[dim].to_sql(dim, con=engine, if_exists='replace', index=False)

    print(f'Insertando fact_ventas ({len(tables["fact_ventas"]):,} filas...)')
    tables['fact_ventas'].to_sql('fact_ventas', con=engine, if_exists='replace', index=False, chunksize=50000)

    print('Carga completa exitosa en SQL Server')





if __name__ == '__main__':
    df = load_and_cache_raw_data()
    audit_raw_data(df)

    df_clean = clean_and_transform(df)

    print('Muestra de datos limpios')
    print(df_clean.head(5))
    print(df_clean[['invoice_no', 'customer_id', 'quantity', 'unit_price', 'total_amount', 'is_cancellation']].head(5))
    
    tables = build_dimensional_model(df_clean)

    # Carga a SQL Server (toma credenciales automáticamente del archivo .env)
    load_to_sql_server(tables)




    
