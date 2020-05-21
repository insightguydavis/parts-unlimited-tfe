variable "netnums" {
  description = "List of strings used to populate the netnum in the cidrsubnet for loop"
  type        = list(number)
  default     = [101, 102, 103]
}