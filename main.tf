provider "aws" {
  region = "ap-southeast-2"
}

# Generate EC2 Key Pair for SSH access
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "taskpem"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

# Security Group to allow SSH access and HTTP/HTTPS if needed
resource "aws_security_group" "allow_ssh_http" {
  name        = "allow_ssh_http"
  description = "Allow SSH, HTTP, and HTTPS"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH from anywhere
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTP access
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTPS access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Allow all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Role for EC2 instance to access CloudWatch and other AWS services
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

# Attach CloudWatchFullAccess to EC2 Role (Optional)
resource "aws_iam_role_policy_attachment" "cloudwatch_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
  role       = aws_iam_role.ec2_role.name
}

# Create IAM instance profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 instance creation
resource "aws_instance" "ec2_instance" {
  ami                    = "ami-084e237ffb23f8f97"  # Amazon Linux 2 AMI
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh_http.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name

  tags = {
    Name = "MyEC2Instance"
  }
}

# Provisioning the EC2 instance to generate SSH keys and clone the private repository
resource "null_resource" "provision_ec2" {
  depends_on = [aws_instance.ec2_instance]

  provisioner "remote-exec" {
    inline = [
      # Update the EC2 instance
      "sudo yum update -y",

      # Install Docker, Git, and other necessary tools
      "sudo yum install docker git amazon-cloudwatch-agent -y",

      # Start Docker service
      "sudo systemctl start docker",

      # Generate SSH Key pair for cloning the private GitHub repo
      "ssh-keygen -t rsa -b 4096 -C 'ec2-instance' -f /home/ec2-user/.ssh/id_rsa -N ''",

      # Output the public key to a file for manual addition to GitHub
      "cat /home/ec2-user/.ssh/id_rsa.pub > /home/ec2-user/ssh-public-key.txt",

      # Add GitHub to the known hosts to avoid manual confirmation when connecting
      "ssh-keyscan -t rsa github.com >> /home/ec2-user/.ssh/known_hosts",

      # Clone the private repository using SSH (add the public key to GitHub first)
      "git clone git@github.com:your-username/your-private-repo.git /home/ec2-user/your-private-repo",

      # Build the Docker image from the repository (if Dockerfile exists)
      "cd /home/ec2-user/your-private-repo && sudo docker build -t myproject .",

      # Run the Docker container, outputting logs to CloudWatch
      "sudo docker run -d -p 80:80 --log-driver=awslogs --log-opt awslogs-group=docker-logs --log-opt awslogs-stream=${aws_instance.ec2_instance.id} --log-opt awslogs-region=ap-southeast-2 myproject",
	  
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
                  "log_stream_name": "${aws_instance.ec2_instance.id}"
                }
              ]
            }
          }
        }
      }
      EOL'
      EOF
      ,

      "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a start -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
    ]

    # SSH connection to the instance for remote execution
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.ec2_key.private_key_pem
      host        = aws_instance.ec2_instance.public_ip
    }
  }
}

# CloudWatch Log Group for Docker logs
resource "aws_cloudwatch_log_group" "log_group" {
  name              = "docker-logs"
  retention_in_days = 30
}

# Output public IP of the EC2 instance
output "ec2_instance_public_ip" {
  value = aws_instance.ec2_instance.public_ip
}
