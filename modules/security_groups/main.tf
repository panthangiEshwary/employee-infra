resource "aws_security_group" "ec2_sg" {
  name        = "mini_project_ec2_sg"
  description = "Allow SSH + App traffic to EC2"
  vpc_id      = var.vpc_id

  # Allow SSH only from your local IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
    description = "SSH Access"
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "App access"
  }
  ingress {
  from_port   = 9100
  to_port     = 9100
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "Node Exporter metrics"
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # OPEN for demo
    description = "App access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "EC2-SG"
    Project = "MiniProject"
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "mini_project_alb_sg"
  description = "Allow HTTP/HTTPS to ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "ALB-SG"
    Project = "MiniProject"
  }
}


resource "aws_security_group" "rds_sg" {
  name        = "mini_project_rds_sg"
  description = "Allow MySQL traffic from EC2 only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
    description     = "Allow MySQL from EC2 only"
  }

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.n8n_sg.id]
    description     = "Allow MySQL from N8N only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "RDS-SG"
    Project = "MiniProject"
  }
}


resource "aws_security_group" "monitor_sg" {
  name        = "monitor-ec2-sg"
  description = "Allow Prometheus, Grafana and SSH access"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "Grafana UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Prometheus UI"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
  description = "Alertmanager UI"
  from_port   = 9093
  to_port     = 9093
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"] # PoC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "MiniProject_MonitorSG"
  }
}


resource "aws_security_group" "n8n_sg" {
  name        = "n8n-sg"
  description = "Allow Alertmanager and UI access"
  vpc_id      = var.vpc_id

  # Allow Alertmanager webhook
  ingress {
    from_port       = 5678
    to_port         = 5678
    protocol        = "tcp"
    security_groups = [aws_security_group.monitor_sg.id]
  }
  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.rds_sg.id]
  }
  # Optional: UI access from your IP (demo)
  ingress {
    from_port   = 5678
    to_port     = 5678
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "n8n-sg"
  }

}
