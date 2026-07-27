output "instance_public_ip" {
  description = "Public IP of the lab host — add this to ansible/inventory/hosts.ini"
  value       = aws_instance.lab.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.lab.id
}

output "ssh_command" {
  description = "Convenience SSH command to reach the host as the default Ubuntu user"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.lab.public_ip}"
}
