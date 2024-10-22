provider "aws" {
  region = "ap-southeast-2"
}

resource "aws_iam_role" "ec2_role" {
  name = "ec2-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      },
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "cloudwatch_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
  role       = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  role       = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_role" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
  role       = aws_iam_role.ec2_role.name
}

resource "aws_security_group" "ec2_sg22" {
  name        = "ec2_security_group46"
  description = "Allow HTTP and SSH traffic"
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "my_instance" {
  ami                    = "ami-084e237ffb23f8f97" # Update with your desired AMI
  instance_type         = "t2.micro"               # Adjust as necessary
  key_name              = "personalawskey"         # Update with your key pair
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name # Corrected reference
  security_groups       = [aws_security_group.ec2_sg22.name]
  
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install git -y
              amazon-linux-extras install docker -y
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user
              # Display the public key
              cat ~/.ssh/id_rsa.pub
              # Clone your repository
              git clone https://github.com/your-repo/agri-pass-backend.git
              cd agri-pass-backend
              docker build -t agri-pass-backend-image .
              docker run -d --name my-app-container -p 80:80 agri-pass-backend-image
              yum install amazon-cloudwatch-agent -y
              # Create the CloudWatch Agent configuration file
              cat << 'EOT' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
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
              EOT
              sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
              EOF
}
