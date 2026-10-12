variable "region" {
  description = "AWSregion for all the resources"
  type        = string
}

variable "project_id" {
  description = "Project identifier used as prefix for resource names and as the Project tag value"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the launch template"
  type        = string
}

variable "public_subnet_a_cidr" {
  description = "CIDR block of public subnet A"
  type        = string
}

variable "public_subnet_b_cidr" {
  description = "CIDR block of public subnet B"
  type        = string
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group"
  type        = number
}

variable "asg_min_size" {
  description = "Minimum number of instances in the Auto Scaling Group"
  type        = number
}

variable "asg_max_size" {
  description = "Maximum number of instances in the Auto Scaling Group"
  type        = number
}

variable "ami" {
  description = "Amazon machine image"
  type        = string
}