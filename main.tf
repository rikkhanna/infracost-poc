terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  # Infracost does not need real AWS credentials to calculate costs.
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

resource "aws_instance" "web_app" {
  ami           = "ami-0c7217cdde317cfec" # Amazon Linux 2023
  instance_type = "m5.large"

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "web-server"
    Environment = "production"
  }
}
