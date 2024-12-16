variable vpccidr {
  description = "Please enter the IP range (CIDR notation) for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable public_subnet_acidr {
  description = "Please enter the IP range (CIDR notation) for the public subnet in the first Availability Zone"
  type        = string
  default     = "10.0.0.0/24"
}

variable public_subnet_bcidr {
  description = "Please enter the IP range (CIDR notation) for the public subnet in the second Availability Zone"
  type        = string
  default     = "10.0.1.0/24"
}

variable private_subnet_acidr {
  description = "Please enter the IP range (CIDR notation) for the private subnet in the first Availability Zone"
  type        = string
  default     = "10.0.2.0/24"
}

variable private_subnet_bcidr {
  description = "Please enter the IP range (CIDR notation) for the private subnet in the second Availability Zone"
  type        = string
  default     = "10.0.3.0/24"
}

variable "environment_name" {
  default = ""
}