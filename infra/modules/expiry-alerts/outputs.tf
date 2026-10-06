output "recipients" {
  value = sort(tolist(local.emails))
}

output "warnings" {
  description = "Per credential: when it expires and when each warning email is due."
  value = {
    for label, expires in var.credentials : label => {
      expires        = expires
      first_warning  = timeadd(expires, "-${var.warning_days * 24}h")
      second_warning = timeadd(expires, "-${(var.warning_days - 30) * 24}h")
      third_warning  = timeadd(expires, "-720h")
    }
  }
}

output "test_alert_secret" {
  value = one(azurerm_key_vault_secret.test[*].name)
}
