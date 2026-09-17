import pandas as pd
from pathlib import Path
import time

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



if __name__ == '__main__':
    df = load_and_cache_raw_data()
    audit_raw_data(df)

    df_clean = clean_and_transform(df)

    print('Muestra de datos limpios')
    print(df_clean.head(5))
    print(df_clean[['invoice_no', 'customer_id', 'quantity', 'unit_price', 'total_amount', 'is_cancellation']].head(5))
    

    

    
