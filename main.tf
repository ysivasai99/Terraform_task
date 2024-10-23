provider "aws" {
  region = "ap-southeast-2" # Specify your preferred AWS region
}

# Key pair resource for SSH access to EC2
resource "aws_key_pair" "ec2_key" {
  key_name   = "sivasaiaws" # Change to your key name
  public_key = file("C:\\Users\\ysiva\\.ssh\\id_rsa.pub") # Path to your public key
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

# IAM Role for EC2 with CloudWatch permissions
resource "aws_iam_role" "ec2_role" {
  name = "EC2CloudWatchRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
        Sid = ""
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
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 instance
resource "aws_instance" "ec2_instance" {
  ami                    = "ami-084e237ffb23f8f97" # Amazon Linux 2 AMI
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.ec2_key.key_name

  vpc_security_group_ids = [aws_security_group.allow_ssh_http.id]

  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name # Associate the instance profile

  tags = {
    Name = "MyEC2Instance"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install docker git -y",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "sudo yum install -y amazon-cloudwatch-agent",
      "sudo mkdir -p /home/ec2-user/agri-pass-backend/logs", # Ensure logs directory exists
      "su - ec2-user -c 'git clone git@github.com:your-repo/agri-pass-backend.git /home/ec2-user/agri-pass-backend'",
      "cd /home/ec2-user/agri-pass-backend",
      "sudo docker build -t agri-pass-backend .",
      "sudo docker run -d --name agri-pass-backend-container -p 80:80 agri-pass-backend",

      # Create CloudWatch configuration file
      Vim /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
      {
        "logs": {
          "logs_collected": {
            "files": {
              "collect_list": [
                {
                  "file_path": "/var/lib/docker/containers/*/*.log",
                  "log_group_name": "docker-logs",
                  "log_stream_name": "{instance_id}"
                }
              ]
            }
          }
        }
      }

      "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a start -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("C:\\Users\\ysiva\\.ssh\\id_rsa")  # Path to your private key
      host        = self.public_ip
    }
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "log_group" {
  name              = "/docker/logs"
  retention_in_days = 30
}

# CloudWatch Log Stream
resource "aws_cloudwatch_log_stream" "log_stream" {
  name           = "my_stream"
  log_group_name = aws_cloudwatch_log_group.log_group.name
}

output "ec2_instance_public_ip" {
  value = aws_instance.ec2_instance.public_ip
}
