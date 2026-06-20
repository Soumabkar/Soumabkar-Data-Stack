from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator

PIPELINE_DIR = "/opt/project/Provisions-Files/project/python/MinIO"
DBT_PROJECT  = "/opt/dbt/lakehouse_project"
DBT_VENV     = "/opt/dbt/dbt-venv"

default_args = {
    "owner": "soumabkar",
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
}

with DAG(
    dag_id="lakehouse_pipeline",
    description="Ingestion pipeline.py puis dbt run + test",
    default_args=default_args,
    schedule="@daily",
    start_date=datetime(2026, 6, 1),
    catchup=False,
    tags=["lakehouse", "dbt", "trino", "minio"],
) as dag:

    ingest = BashOperator(
        task_id="ingest_pipeline",
        bash_command=(
            f"cd {PIPELINE_DIR} && source venv/bin/activate && python3 pipeline.py"
        ),
    )

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=(
            f"source {DBT_VENV}/bin/activate && cd {DBT_PROJECT} && "
            f"dbt run --target airflow"
        ),
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            f"source {DBT_VENV}/bin/activate && cd {DBT_PROJECT} && "
            f"dbt test --target airflow"
        ),
    )

    ingest >> dbt_run >> dbt_test
