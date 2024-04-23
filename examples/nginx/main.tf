module "main" {
  source    = "../../"
  code_path = "./code"
}

output "ex" {
  value = module.main.ex
}
