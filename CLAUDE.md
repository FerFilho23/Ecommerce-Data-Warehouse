# CLAUDE.md — Ecommerce Data Warehouse

Portfolio data warehouse on GCP for the Olist Brazilian e-commerce dataset.
Medallion architecture (bronze → silver → gold) in BigQuery, transformed with dbt,
orchestrated by Airflow, provisioned with Terraform, dbt shipped to Cloud Run via Cloud Build.

## Project status — read this first

The repo is early-stage. Know what exists before assuming anything does.

| Component | Status | Location |
| --- | --- | --- |
| Terraform (SAs, IAM, GCS bucket + CSV upload, Cloud Build trigger) | ✅ exists | `terraform/` |
| Cloud Build pipeline (build → push → deploy Cloud Run) | ⚠️ exists, has bugs (see Known issues) | `cloud_run_dbt/cloudbuild.yml` |
| Sample dataset (~500 rows/table) | ✅ exists | `datasets/olist_ecommerce_dataset/` |
| BigQuery datasets (bronze/silver/gold) | ❌ not provisioned yet | add to `terraform/bigquery.tf` |
| dbt project | ❌ not created yet | `cloud_run_dbt/dbt/` (path already in `.gitignore`) |
| Dockerfile for dbt image | ❌ missing | `cloud_run_dbt/Dockerfile` |
| Airflow (local Docker) + DAGs | ❌ only `airflow/keys/` placeholder | `airflow/` |

Never invent files, models or DAGs as if they already exist. When adding a planned
component, follow the target layout below.

## Architecture & data flow

```
datasets/*.csv ──terraform──▶ GCS bucket (ecommerce_data_staging)
                                   │  Airflow: GCSToBigQueryOperator
                                   ▼
                     BigQuery bronze  (raw, 1:1 with CSVs, all STRING-safe)
                                   │  Airflow → invokes Cloud Run (dbt)
                                   ▼
                     BigQuery silver  (dbt staging/intermediate: typed, cleaned, deduped)
                                   ▼
                     BigQuery gold    (dbt marts: star schema fct_/dim_)
```

- GCP project: `hallowed-nectar-509600-h4`, region `us-central1` (BigQuery location must match the bucket: `us-central1`).
- Service accounts (Terraform-managed):
  - `dbt-runner-sa` — runtime identity of the Cloud Run dbt service (BQ dataEditor/jobUser/user).
  - `airflow-runner-sa` — Airflow; loads GCS → BQ and invokes Cloud Run (`run.invoker`). Key file → `airflow/keys/airflow_service_account.json`.
  - `cloudbuild-runner-sa` — builds/pushes image to Artifact Registry repo `cloud-run`, deploys service `pipeline-ecommerce-bq-dbt`.
- Cloud Build trigger fires on push to `main` only when `cloud_run_dbt/**` changes.

## Target repo layout (follow when creating new pieces)

```
terraform/            # all GCP infra; one file per concern (gcs.tf, bigquery.tf, iam_*.tf ...)
cloud_run_dbt/
  Dockerfile          # python:3.13-slim + dbt-bigquery; entrypoint runs dbt
  cloudbuild.yml
  dbt/                # dbt project root (dbt_project.yml, profiles.yml, models/, tests/, macros/)
airflow/
  docker-compose.yml  # local Airflow
  dags/               # one DAG file per pipeline
  keys/               # SA key — NEVER commit real keys
datasets/             # sample CSVs only; full dataset comes from Kaggle
docs/                 # architecture diagram (.drawio + .png) — update both together
```

## Commands

### Terraform (run from `terraform/`)
```bash
terraform init && terraform fmt -recursive && terraform validate
terraform plan                       # ALWAYS show plan output before any apply
terraform apply                      # only when the user explicitly asks
terraform output -json > outputs_tf.json
jq -r '.airflow_service_account_key_base64.value' outputs_tf.json | base64 --decode > ../airflow/keys/airflow_service_account.json
```

### dbt (run from `cloud_run_dbt/dbt/`)
```bash
dbt deps
dbt debug                            # verify BigQuery connection first
dbt build --select <model>+          # run + test a model and its children
dbt build --select state:modified+ --defer --state <prod_manifest_dir>  # when manifest is available
dbt compile --select <model>         # inspect generated SQL before running
dbt docs generate
```
Locally authenticate with `gcloud auth application-default login` (profile `method: oauth`);
in Cloud Run use the attached service account (no key files).

### Airflow (from `airflow/`)
```bash
docker compose up -d
docker compose exec airflow-scheduler airflow dags list-import-errors
docker compose exec airflow-scheduler airflow dags test <dag_id> <yyyy-mm-dd>
```

## dbt conventions

- Layers map to BigQuery datasets via `+schema` in `dbt_project.yml`:
  - `models/staging/` → **silver**: `stg_olist__<entity>.sql`, one per source table, views. Only rename, cast, trim, dedupe. No joins.
  - `models/intermediate/` → **silver**: `int_<entity>__<verb>.sql`, ephemeral or views. Joins/business logic.
  - `models/marts/` → **gold**: `fct_<event>.sql` / `dim_<entity>.sql`, tables.
- Override `generate_schema_name` so `+schema: silver` yields exactly `silver` (not `<target>_silver`) in prod; keep the prefix in dev.
- Sources declared once in `models/staging/_olist__sources.yml` pointing at the bronze dataset, with `loaded_at_field` + freshness where a timestamp exists.
- Every model has a YAML entry with a description. Every primary key gets `unique` + `not_null`; every FK gets `relationships`.
- Use `{{ ref() }}` / `{{ source() }}` always — never hardcode project/dataset names in SQL.
- SQL style: lowercase keywords, CTEs (`with source as (...), renamed as (...) select * from renamed`), trailing commas, one column per line, explicit column lists in marts (no `select *` in gold).
- BigQuery cost/perf: partition large facts by date (`partition_by={'field': 'order_purchase_date', 'data_type': 'date'}`), cluster by common filter keys (e.g. `customer_id`, `seller_id`). Use `incremental` + `merge` only when volume justifies it; the sample data does not.
- Monetary columns: `numeric`. Timestamps: cast to `timestamp`, derive `date` columns for partitioning.

### Olist domain notes (gotchas)
- Grain: `orders` 1 row/order; `order_items` 1 row/item (`order_id` + `order_item_id`); `payments` can have multiple rows/order (`payment_sequential`); `reviews` may have duplicate `review_id`s — dedupe in staging.
- `customer_id` is per-order; the real person is `customer_unique_id`. Build `dim_customers` on `customer_unique_id`.
- `geolocation` has many rows per zip prefix — aggregate (e.g. avg lat/lng) before joining.
- Product category names are Portuguese; translate via `product_category_name_translation`. Column names contain typos (`product_name_lenght`) — fix in staging.
- Sample data has ~500 random rows/table, so referential integrity WILL fail; set `relationships` tests to `severity: warn` while using the sample.

## Airflow conventions

- DAGs are thin orchestration only: load (GCS → bronze) then trigger dbt. No transformation logic in Python.
- Use provider operators (`GCSToBigQueryOperator`, Cloud Run operators / authenticated HTTP call) over `BashOperator`.
- Idempotent tasks: bronze loads use `write_disposition="WRITE_TRUNCATE"`; dbt is re-runnable.
- `catchup=False`, explicit `start_date`, `default_args` with retries, tags `["ecommerce", "<layer>"]`.
- Connections/variables come from env vars or Airflow connections — no hardcoded project IDs or key paths in DAG code.
- Dynamic task mapping (`.expand()`) over the list of tables instead of copy-pasted tasks.

## Terraform conventions

- Reference `var.project_id` / resource attributes — never hardcode the project ID or SA emails.
- Grant least privilege; prefer dataset/bucket-level IAM over project-level when adding new roles.
- Run `terraform fmt` and `validate` after every change; show `plan` diffs to the user.
- Never run `terraform apply` or `terraform destroy` without explicit confirmation.

## Known issues (fix opportunistically, mention when relevant)

1. `cloudbuild.yml` `_PATH` is `GCP/pipeline-ecommerce-bq-dbt/cloud_run_dbt` — wrong for this repo; should be `cloud_run_dbt`.
2. No `cloud_run_dbt/Dockerfile` yet, so the Cloud Build pipeline cannot succeed.
3. Cloud Run *service* expects an HTTP server; for batch `dbt build` a **Cloud Run Job** is a better fit (Airflow `CloudRunExecuteJobOperator`). Confirm with the user before switching.
4. `cloud_build.tf` hardcodes the project ID in the trigger's `service_account`; also declares variables outside `variables.tf`.
5. `gcs.tf`: lifecycle comment says 2 days but `age = 30`; `gcs_bucket_name_prefix` is used as the full name (project ID is not appended despite the description).
6. No BigQuery datasets in Terraform; no remote state backend (local `tfstate`).
7. `airflow/keys/*.json` is NOT in `.gitignore` — add it before generating a real key.

## Security rules (non-negotiable)

- Never commit or print service-account keys, `outputs_tf.json`, `.env`, or `*.tfstate`.
- The committed `airflow/keys/airflow_service_account.json` is a placeholder; keep it that way.
- Prefer ADC / attached service accounts over key files wherever possible.

## Workflow for Claude

1. Before editing, check whether the component exists (see status table); read neighbouring files to match style.
2. Make small, reviewable changes; one concern per commit (`feat(dbt): ...`, `fix(terraform): ...`, `chore(airflow): ...`).
3. After dbt changes: `dbt build --select <changed>+`. After Terraform changes: `fmt` + `validate` + `plan`. After DAG changes: check import errors.
4. If something can't be verified (no GCP credentials in the session), say so explicitly instead of claiming success.
5. Update `README.md` and this file when the architecture, status table or commands change.
