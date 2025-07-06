terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31.0"
    }
  }

  required_version = ">= 1.6.6"
}

variable "aws_region" {
  type = string
  description = "AWS region to deploy into"
}

provider "aws" {
  region              = var.aws_region
}

# for ACM cert for CloudFront
# https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html#https-requirements-aws-region
provider "aws" {
  region              = "us-east-1"
  alias               = "us-east-1"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_canonical_user_id" "current" {}
