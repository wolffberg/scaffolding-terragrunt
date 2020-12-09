variable "repository_name" {
  description = "Name of this repository. Will be used to name resources"
  type        = string
}

variable "trusted_identities" {
  description = "List of trusted identities allowed to manage the remote state"
  type        = list(string)
}
