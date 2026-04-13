###############################################################################
# modules/eks/variables.tf
###############################################################################

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "vpc_id" {
  description = "VPC ID where EKS will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for EKS control plane and node groups"
  type        = list(string)
}

variable "cluster_security_group_id" {
  description = "Security group ID for EKS cluster control plane"
  type        = string
}

variable "node_security_group_id" {
  description = "Security group ID for EKS Fargate pods (used for Security Groups for Pods)"
  type        = string
}

variable "fargate_profiles" {
  description = "Map of Fargate profiles. Each profile defines namespace selectors for pod scheduling."
  type = map(object({
    selectors = list(object({
      namespace = string
      labels    = optional(map(string), {})
    }))
  }))
  default = {
    apps = {
      selectors = [
        { namespace = "default", labels = {} },
        { namespace = "production", labels = {} }
      ]
    }
    debezium = {
      selectors = [
        { namespace = "debezium", labels = {} }
      ]
    }
  }
}

variable "enable_cluster_log_types" {
  description = "EKS control-plane log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_endpoint_private_access" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs that may access the public API endpoint"
  type        = list(string)
  default     = []
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts (OIDC)"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# ---- KMS & Logging ----------------------------------------------------------

variable "kms_deletion_window_in_days" {
  description = "Waiting period (days) before KMS key is deleted after destroy"
  type        = number
  default     = 7
}

variable "log_retention_days" {
  description = "CloudWatch log group retention period in days for EKS control-plane logs"
  type        = number
  default     = 90
}

# ---- Node Group Rolling Update ----------------------------------------------

variable "max_unavailable_percentage" {
  description = "Maximum percentage of nodes that can be unavailable during a managed node group update"
  type        = number
  default     = 25
}

# ---- Tags -------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
