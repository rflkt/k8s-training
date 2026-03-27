resource "google_storage_bucket" "bucket" {
  name          = var.bucket_name
  location      = var.location
  force_destroy = var.force_destroy

  versioning {
    enabled = var.versioning_enabled
  }

  labels = var.labels

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_age_days != null ? [1] : []
    content {
      condition {
        age = var.lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }

  uniform_bucket_level_access = true
}
