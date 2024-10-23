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

# EC2 instance
resource "aws_instance" "ec2_instance" {
  ami           = "ami-084e237ffb23f8f97" # Amazon Linux 2 AMI
  instance_type = "t2.micro"
  key_name      = aws_key_pair.ec2_key.key_name  # Fix the key_name reference

  vpc_security_group_ids = [aws_security_group.allow_ssh_http.id]

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
	  
      "git clone https://github.com/agri-pass/agri-pass-backend.git",
      "cd project",
      "sudo docker build -t myproject .",
      "sudo docker run -d -p 80:80 --log-driver=awslogs --log-opt awslogs-group=/docker/logs --log-opt awslogs-stream=my_stream --log-opt awslogs-region=ap-southeast-2 -v /var/log/docker_logs:/var/log/app_logs myproject",

      # Install CloudWatch Agent
      "sudo yum install amazon-cloudwatch-agent -y",

      # Create CloudWatch Agent configuration file
      "sudo bash -c 'cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOL\n" +
      "{\n" +
      "  \"logs\": {\n" +
      "    \"logs_collected\": {\n" +
      "      \"files\": {\n" +
      "        \"collect_list\": [\n" +
      "          {\n" +
      "            \"file_path\": \"/var/lib/docker/containers/*.log\",\n" +
      "            \"log_group_name\": \"docker-logs\",\n" +
      "            \"log_stream_name\": \"{instance_id}\"\n" +
      "          }\n" +
      "        ]\n" +
      "      }\n" +
      "    }\n" +
      "  }\n" +
      "}\n" +
      "EOL'",

      # Start CloudWatch Agent
      "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a start -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("C:\\Users\\ysiva\\.ssh\\id_rsa") # Use correct private key path
      host        = self.public_ip
    }
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "log_group" {
  name              = "docker-logs"  # CloudWatch log group for Docker logs
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
