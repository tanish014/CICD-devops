output "cicd_public_ip" {
  value = aws_instance.cicd.public_ip
}

output "jenkins_url" {
  value = "http://${aws_instance.cicd.public_ip}:8080"
}

output "github_webhook_url" {
  value = "http://${aws_instance.cicd.public_ip}:8080/github-webhook/"
}

output "app_public_ip" {
  value = aws_instance.app.public_ip
}

output "app_private_ip" {
  description = "Put this in the APP_HOST variable of the Jenkinsfile"
  value       = aws_instance.app.private_ip
}

output "dashboard_url" {
  value = "http://${aws_instance.app.public_ip}:30080"
}

output "grafana_url" {
  value = "http://${aws_instance.app.public_ip}:30030"
}

output "prometheus_url" {
  value = "http://${aws_instance.app.public_ip}:30090"
}
