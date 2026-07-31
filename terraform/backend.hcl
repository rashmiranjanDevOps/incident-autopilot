# Filled in by hand, once, after running scripts/bootstrap-backend.sh —
# that script prints the exact bucket name (it includes your AWS account ID)
# to put on the line below. Terraform's `backend` block can't take variables,
# so this can't be templated automatically; it's a one-time manual edit.

bucket         = "incident-autopilot-tfstate-897074277336"
key            = "terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "incident-autopilot-tf-locks"
encrypt        = true
