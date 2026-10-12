locals {
  common_tags = {
    Terraform = "true"
    Project   = var.project_id
  }

  vpc_name              = "${var.project_id}-vpc"
  ec2_sg_name           = "${var.project_id}-ec2_sg"
  http_sg_name          = "${var.project_id}-http_sg"
  lb_sg_name            = "${var.project_id}-sglb"
  instance_profile_name = "${var.project_id}-instance_profile"
  key_pair_name         = "${var.project_id}-keypair"
  launch_template_name  = "${var.project_id}-template"
  asg_name              = "${var.project_id}-asg"
  lb_name               = "${var.project_id}-loadbalancer"
  tg_name               = "${var.project_id}-tg"

  user_data = <<-EOT
    #!/bin/bash
    set -e
    dnf update -y
    dnf install -y httpd jq
    systemctl enable httpd
    systemctl start httpd

    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

    echo "This message was generated on instance $INSTANCE_ID with the following IP: $PRIVATE_IP" > /var/www/html/index.html
  EOT
}

# ---------- Pre-created resources ----------
data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnet" "public_a" {
  vpc_id     = data.aws_vpc.this.id
  cidr_block = var.public_subnet_a_cidr
}

data "aws_subnet" "public_b" {
  vpc_id     = data.aws_vpc.this.id
  cidr_block = var.public_subnet_b_cidr
}

data "aws_security_group" "ec2" {
  vpc_id = data.aws_vpc.this.id
  name   = local.ec2_sg_name
}

data "aws_security_group" "http" {
  vpc_id = data.aws_vpc.this.id
  name   = local.http_sg_name
}

data "aws_security_group" "lb" {
  vpc_id = data.aws_vpc.this.id
  name   = local.lb_sg_name
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------- Launch Template ----------
resource "aws_launch_template" "this" {
  name          = local.launch_template_name
  image_id      = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type
  key_name      = local.key_pair_name
  user_data     = base64encode(local.user_data)

  iam_instance_profile {
    name = local.instance_profile_name
  }

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups             = [data.aws_security_group.ec2.id, data.aws_security_group.http.id]
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "optional"
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${var.project_id}-instance" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tags = local.common_tags
}

# ---------- Load Balancer ----------

resource "aws_lb_target_group" "this" {
  name     = local.tg_name
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.this.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }

  tags = local.common_tags
}

resource "aws_lb" "this" {
  name               = local.lb_name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [data.aws_security_group.lb.id]
  subnets            = [data.aws_subnet.public_a.id, data.aws_subnet.public_b.id]

  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = local.common_tags
}


#Auto Scaling Group 
resource "aws_autoscaling_group" "this" {
  name                = local.asg_name
  desired_capacity    = var.asg_desired_capacity
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  vpc_zone_identifier = [data.aws_subnet.public_a.id, data.aws_subnet.public_b.id]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    ignore_changes = [load_balancers, target_group_arns]
  }
}

resource "aws_autoscaling_attachment" "this" {
  autoscaling_group_name = aws_autoscaling_group.this.id
  lb_target_group_arn    = aws_lb_target_group.this.arn
}