provider "aws" {
  region = "ap-southeast-2" # Specify your preferred AWS region
}

# Generate a new EC2 Key Pair
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "sivasaiaws" # Key name for EC2
  public_key = tls_private_key.ec2_key.public_key_openssh
}

# Security group allowing SSH and HTTP access
resource "aws_security_group" "allow_ssh_http" {
  name        = "allow_ssh_http"
  description = "Allow SSH and HTTP"

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

# IAM role for EC2 to allow CloudWatch access
resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach CloudWatchFullAccess policy to the IAM role
resource "aws_iam_role_policy_attachment" "cloudwatch_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
  role       = aws_iam_role.ec2_role.name
}

# Create an IAM instance profile
resource "aws_iam_instance_profile" "ec2_instance_profile123" {
  name = "ec2_instance_profile123"
  role = aws_iam_role.ec2_role.name
}

# EC2 instance
resource "aws_instance" "ec2_instance" {
  ami                    = "ami-084e237ffb23f8f97" # Amazon Linux 2 AMI
  instance_type          = "t2.micro"
  key_name               = "sivasaiaws"
  vpc_security_group_ids = [aws_security_group.allow_ssh_http.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile123.name

  tags = {
    Name = "MyEC2Instance"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install docker git -y",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "sudo yum install -y awslogs",
      "sudo service awslogs start",
      "sudo mkdir -p /var/log/docker_logs",

      # Clone the repository via HTTPS (since no SSH key)
      "git clone https://github.com/agri-pass/agri-pass-backend.git /home/ec2-user/agri-pass-backend",
      "cd /home/ec2-user/agri-pass-backend",
      "sudo docker build -t myproject .",
      "sudo docker run -d -p 80:80 --log-driver=awslogs --log-opt awslogs-group=docker-logs --log-opt awslogs-stream={instance_id} --log-opt awslogs-region=ap-southeast-2 -v /var/log/docker_logs:/var/log/app_logs myproject",

      # Install CloudWatch Agent
      "sudo yum install amazon-cloudwatch-agent -y",

      # Create CloudWatch Agent configuration file using a heredoc
      <<-EOF
      sudo bash -c 'cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOL
      {
        "logs": {
          "logs_collected": {
            "files": {
              "collect_list": [
                {
                  "file_path": "/var/lib/docker/containers/*.log",
                  "log_group_name": "docker-logs",
                  "log_stream_name": "{instance_id}"
                }
              ]
            }
          }
        }
      }
      EOL'
      EOF
      ,

      # Start CloudWatch Agent
      "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a start -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.ec2_key.private_key_pem
      host        = self.public_ip
    }
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "log_group" {
  name              = "docker-logs"
  retention_in_days = 30
}

# Output public IP of the instance
output "ec2_instance_public_ip" {
  value = aws_instance.ec2_instance.public_ip
}
