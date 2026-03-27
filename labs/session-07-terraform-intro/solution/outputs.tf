output "bucket_name" {
  description = "Name of the created GCS bucket"
  value       = google_storage_bucket.training.name
}

output "bucket_url" {
  description = "URL of the created GCS bucket"
  value       = google_storage_bucket.training.url
}
