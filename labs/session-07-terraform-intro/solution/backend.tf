terraform {
  backend "gcs" {
    bucket = "training-tfstate"
    prefix = "terraform/intro"
  }
}
