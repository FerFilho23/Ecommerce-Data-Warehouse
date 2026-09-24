
variable "branch_name" {
  description = "The branch name to trigger builds on (e.g., 'main', 'master')."
  type        = string
  default     = "main"
}

variable "repo_owner" {
  description = "The owner (username or organization) of the GitHub repository."
  type        = string
  default     = "FerFilho23"
}

variable "repo_name" {
  description = "The name of the GitHub repository."
  type        = string
  default     = "Ecommerce-Data-Warehouse"
}

variable "cloudbuild_connection_name" {
  description = "A unique name for the Cloud Build Connection resource."
  type        = string
  default     = "ecommerce_data_warehouse"
}

# Cloud Build Connection to GitHub
# 1. Cloud Build Trigger
resource "google_cloudbuild_trigger" "main_branch_trigger" {
  project  = var.project_id
  location = "global"
  name     = "pipeline-ecommerce-bq-dbt-trigger"
  description = "Triggers build on push to ${var.branch_name} branch"
  filename  = "cloud_run_dbt/cloudbuild.yml"

  github {
    owner = var.repo_owner
    name  = var.repo_name
    push {
      # Use regex for exact branch match. Use ".*" for any branch.
      branch = "^${var.branch_name}$"
    }
  }

  included_files = ["cloud_run_dbt/**"]
  service_account = "projects/hallowed-nectar-509600-h4/serviceAccounts/${google_service_account.cloud_build_service_account.email}"
  include_build_logs = "INCLUDE_BUILD_LOGS_WITH_STATUS"

}


