terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# TODO: Create a GCS bucket with the following configuration:
# - resource type: google_storage_bucket
# - name: var.bucket_name
# - location: var.region
# - force_destroy: true (for easy cleanup during training)
#
# TODO: Add versioning block:
#   versioning {
#     enabled = true
#   }
#
# TODO: Add labels:
#   labels = {
#     environment = "training"
#     managed_by  = "terraform"
#   }
#
# TODO: Add a lifecycle_rule to delete objects older than 30 days:
#   lifecycle_rule {
#     condition {
#       age = 30
#     }
#     action {
#       type = "Delete"
#     }
#   }
