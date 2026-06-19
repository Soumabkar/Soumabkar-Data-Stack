# Installation des modèles dbt dans lakehouse_project

## 1. Supprimer les modèles d'exemple

```bash
rm -rf ~/dbt/lakehouse_project/models/example
```

## 2. Copier les nouveaux modèles

```bash
cp -r staging/ marts/ ~/dbt/lakehouse_project/models/
cp dbt_project.yml ~/dbt/lakehouse_project/
```

## 3. S'assurer que le pipeline a tourné (tables sources nécessaires)

```bash
cd ~/Soumabkar-Data-Stack/Provisions-Files/project/python/MinIO
source venv/bin/activate
python3 pipeline.py
deactivate
```

## 4. Lancer dbt

```bash
cd ~/dbt/lakehouse_project
source ~/dbt/dbt-venv/bin/activate

dbt run    # crée les vues staging + tables marts
dbt test   # 11 tests de qualité
```

## Résultat attendu

```
Found 7 models, 11 data tests
staging/stg_customers         [OK]
staging/stg_products          [OK]
staging/stg_orders            [OK]
marts/mart_revenue_by_category [OK]
marts/mart_monthly_sales       [OK]
marts/mart_top_customers       [OK]
marts/mart_cancellation_rate   [OK]
PASS=7 ERROR=0
```
