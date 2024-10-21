provider "aws" {
  region = "ap-southeast-2"
}

resource "aws_instance" "agri_pass_ec2_instance" {
  ami           = "ami-084e237ffb23f8f97"  # Amazon Linux 2 AMI
  instance_type = "t2.micro"                # Use appropriate instance type
  key_name      = "personalawskey"          # Use the existing key pair

  iam_instance_profile = aws_iam_instance_profile.ec2_role.name

  security_groups = [aws_security_group.ec2_security_group.name]

  user_data = <<-EOF
    #!/bin/bash
    # Update and install Docker and Git
    yum update -y
    yum install -y docker git
    service docker start
    usermod -a -G docker ec2-user

    # Install CloudWatch Logs agent
    yum install -y amazon-cloudwatch-agent

    # Clone the backend repository
    git clone https://github.com/agri-pass/agri-pass-backend.git /home/ec2-user/agri-pass-backend

    # Run the Docker container
    cd /home/ec2-user/agri-pass-backend
    docker build -t agri-pass-backend .
    docker run -d --name agri-pass-backend -p 80:80 agri-pass-backend

    # Create the CloudWatch Logs config file
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<-CWLOGCONFIG
    {
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/lib/docker/containers/*/*.log",
                "log_group_name": "${aws_cloudwatch_log_group.agri_pass_log_group.name}",
                "log_stream_name": "{instance_id}"
              }
            ]
          }
        }
      }
    }
    CWLOGCONFIG

    # Start the CloudWatch agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

  EOF

  tags = {
    Name = "AgriPass-EC2"
  }
}

resource "aws_security_group" "ec2_security_group" {
  name        = "agri-pass-sg"
  description = "Allow HTTP and SSH traffic"

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

resource "aws_iam_role" "ec2_role" {
  name = "agri_pass_ec2_role"

  assume_role_policy = <<-POLICY
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        }
      }
    ]
  }
  POLICY
}

resource "aws_iam_instance_profile" "ec2_role" {
  name = "agri_pass_ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"  # Grant full CloudWatch access
}

resource "aws_cloudwatch_log_group" "agri_pass_log_group" {
  name              = "/var/log/agri-pass-backend"
  retention_in_days = 14  # Adjust log retention as needed
}
