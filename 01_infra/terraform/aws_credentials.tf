variable "aws_region" {
	default = "eu-west-1"
}

variable "aws_access" {
	default = "AKIAIPP3IAAO4CJTFRSQ"
}

variable "aws_secret" {
	default = "mCEgHR9w3wCxQmf7hhA3D82OYwIAXx0tNQ/bCIoW"
}

provider "aws" {
	version 		= "~> 1.20"

	region 		= "${var.aws_region}"
	access_key	= "${var.aws_access}"
	secret_key	= "${var.aws_secret}"
}
