# Medidas y Columnas DAX

## Medidas (Tabla _Medidas)

### Ventas Totales
```dax
Ventas Totales = SUM(fact_ventas[total_amount])
```

### Volumen de Ordenes
```dax
Volumen de Ordenes = DISTINCTCOUNT(fact_ventas[invoice_no])
```

### Ticket Promedio
```dax
Ticket Promedio = DIVIDE([Ventas Totales], [Volumen de Ordenes], 0)
```

### Margen Estimado
```dax
Margen Estimado = [Ventas Totales] * 0.35
```

### Ventas Mes Anterior
```dax
Ventas Mes Anterior = 
CALCULATE(
    [Ventas Totales],
    DATEADD(dim_tiempo[fecha], -1, MONTH)
)
```

### Crecimiento MoM %
```dax
Crecimiento MoM % = 
DIVIDE(
    [Ventas Totales] - [Ventas Mes Anterior],
    [Ventas Mes Anterior],
    0
)
```

### Clientes Totales
```dax
Clientes Totales = COUNTROWS(dim_cliente)
```

### Tasa de Churn %
```dax
Tasa de Churn % = 
DIVIDE(
    COUNTROWS(FILTER(vw_segmentacion_rfm, vw_segmentacion_rfm[dias_recencia] > 90)),
    COUNTROWS(vw_segmentacion_rfm),
    0
)
```

---

## Columnas Calculadas (Tabla dim_tiempo)

### AnoMes_Num
```dax
AnoMes_Num = dim_tiempo[year] * 100 + dim_tiempo[month_number]
```

### Mes Ano
```dax
Mes Ano = FORMAT(dim_tiempo[fecha], "mmm yyyy")
```
