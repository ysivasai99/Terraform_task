#!/bin/bash

# Update the package index
yum update -y

# Install Git
yum install git -y

# Install Docker
yum install docker -y

# Start the Docker service
service docker start

# Enable Docker to start on boot
systemctl enable docker

# Install the AWS CloudWatch Agent
yum install amazon-cloudwatch-agent -y

# Create a configuration file for CloudWatch Logs
cat <<EOL > /etc/cloudwatch-agent-config.json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/lib/docker/containers/*/*.log",
            "log_group_name": "/aws/docker/backend-logs-unique-2024",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 14
          }
        ]
      }
    }
  }
}
EOL

# Start the CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -s -c file:/etc/cloudwatch-agent-config.json

# Optional: Run a Docker container (e.g., NGINX or any other application)
# Uncomment the line below to run an NGINX container
# docker run -d -p 80:80 nginx
