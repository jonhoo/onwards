terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.6.6"
}

variable "aws_region" {
  type        = string
  description = "AWS region to deploy into"
}

provider "aws" {
  region = var.aws_region
}

# for ACM cert for CloudFront
# https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html#https-requirements-aws-region
provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_canonical_user_id" "current" {}

# prod
terraform {
  backend "s3" {
    # CHANGEME NOTE: You will need to change the value of the bucket and the
    # region below to reflect your own domain and preferred region! This should
    # be the only diff you have to the infrastructure files compared to
    # jonhoo/onwards.
    bucket = "onwards.r4r.fyi.terraform"
    region = "eu-north-1"
    key    = "prod/terraform.tfstate"
  }
}
