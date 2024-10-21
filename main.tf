provider "aws" {
  region = "ap-southeast-2"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "docker_log_group" {
  name              = "/aws/docker/backend-logs-unique-2024"
  retention_in_days = 14
}

# CloudWatch Metric Filter
resource "aws_cloudwatch_log_metric_filter" "error_filter" {
  name           = "ErrorFilterUnique2024"
  log_group_name = aws_cloudwatch_log_group.docker_log_group.name
  pattern        = "ERROR"

  metric_transformation {
    name      = "ErrorCountUnique2024"
    namespace = "YourNamespaceUnique2024"
    value     = "1"
  }
}

# CloudWatch Metric Alarm
resource "aws_cloudwatch_metric_alarm" "error_alarm" {
  alarm_name          = "ErrorCountAlarmUnique2024"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ErrorCountUnique2024"
  namespace           = "YourNamespaceUnique2024"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
}

# IAM Role for EC2 instance
resource "aws_iam_role" "ec2_instance_role" {
  name = "EC2CloudWatchRoleUnique2024"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach CloudWatch Logs policy to the role
resource "aws_iam_role_policy_attachment" "attach_cw_logs_policy" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# IAM Instance Profile for EC2
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "EC2InstanceProfileUnique2024"
  role = aws_iam_role.ec2_instance_role.name  # Corrected line
}

# Security Group for EC2 instance
resource "aws_security_group" "ec2_sg" {
  name        = "AllowSSHHTTPTrafficUnique2024"
  description = "Allow SSH and HTTP inbound traffic"
  vpc_id      = "vpc-07e75756a2cacf2a8"  # Update with your VPC ID

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instance with IAM role
resource "aws_instance" "docker_ec2" {
  ami                    = "ami-12345678"  # Replace with your AMI ID
  instance_type         = "t2.micro"
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups        = [aws_security_group.ec2_sg.name]
  user_data              = file("${path.module}/user_data.sh")  # Ensure the correct path to your script

  tags = {
    Name = "DockerInstanceUnique2024"
  }
}
