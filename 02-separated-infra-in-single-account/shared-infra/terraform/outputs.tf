output "vpc_id" {
  value       = aws_vpc.this.id
  description = "VPCのID"
}
output "lb_listener_arn" {
  value       = aws_lb_listener.this.arn
  description = "ALBのlistenerのarn"
}
output "public_subnet_ids" {
  value = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id,
  ]
  description = "public subnetのIDのlist"
}
