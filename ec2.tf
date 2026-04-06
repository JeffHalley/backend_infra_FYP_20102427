############################################
# data sources
############################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-arm64"]
  }
}

resource "aws_security_group" "postgres" {
  name        = "postgres-spot-sg"
  description = "Postgres access from Lambda"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "postgres" {
  ami           = data.aws_ami.al2023_arm.id
  instance_type = "t4g.small"
  subnet_id     = data.aws_subnets.default.ids[0]

  vpc_security_group_ids = [aws_security_group.postgres.id]

  key_name = "postgress_instance_keypair"

  user_data = <<-EOF
    #!/bin/bash
    set -e
    dnf update -y
    dnf install -y postgresql16-server
    /usr/bin/postgresql-setup --initdb
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /var/lib/pgsql/data/postgresql.conf
    echo "host all all 0.0.0.0/0 scram-sha-256" >> /var/lib/pgsql/data/pg_hba.conf
    systemctl enable postgresql
    systemctl start postgresql
  EOF

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type             = "persistent"
      instance_interruption_behavior = "stop"
    }
  }

  lifecycle {
    ignore_changes = [ami, user_data, instance_type]
  }

  tags = { Name = "postgres-spot" }
}
