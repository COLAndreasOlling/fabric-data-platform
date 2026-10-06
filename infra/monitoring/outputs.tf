output "recipients" {
  value = module.expiry_alerts.recipients
}

output "warnings" {
  description = "Per credential: expiry and the dates of the warning emails."
  value       = module.expiry_alerts.warnings
}

output "test_alert_secret" {
  description = "Name of the test marker (expires 10 minutes after apply), if send_test_alert is on."
  value       = module.expiry_alerts.test_alert_secret
}
