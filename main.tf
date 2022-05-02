resource "aws_vpc" "demo_vpc" {
  cidr_block       = "10.1.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "Demo VPC"
  }
}

resource "aws_subnet" "private_us_west_2a" {
  vpc_id     = aws_vpc.demo_vpc.id
  cidr_block = "10.1.0.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "Private Subnet us-west-2a"
  }
}

resource "aws_subnet" "private_us_west_2b" {
  vpc_id     = aws_vpc.demo_vpc.id
  cidr_block = "10.1.1.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "Public Subnet us-west-2b"
  }
}

resource "aws_subnet" "private_us_west_2c" {
  vpc_id     = aws_vpc.demo_vpc.id
  cidr_block = "10.1.2.0/24"
  availability_zone = "us-west-2c"

  tags = {
    Name = "Private Subnet us-west-2c"
  }
}

resource "aws_subnet" "private_us_west_2d" {
  vpc_id     = aws_vpc.demo_vpc.id
  cidr_block = "10.1.3.0/24"
  availability_zone = "us-west-2d"

  tags = {
    Name = "Private Subnet us-west-2d"
  }
}


resource "aws_internet_gateway" "my_vpc_igw" {
  vpc_id = aws_vpc.demo_vpc.id

  tags = {
    Name = "My VPC - Internet Gateway"
  }
}

resource "aws_route_table" "my_vpc_private" {
    vpc_id = aws_vpc.demo_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.my_vpc_igw.id
    }

    tags = {
        Name = "Private Subnets Route Table for My VPC"
    }
}

resource "aws_route_table_association" "my_vpc_us_west_2a_private" {
    subnet_id = aws_subnet.private_us_west_2a.id
    route_table_id = aws_route_table.my_vpc_private.id
}

resource "aws_route_table_association" "my_vpc_us_west_2b_public" {
    subnet_id = aws_subnet.private_us_west_2b.id
    route_table_id = aws_route_table.my_vpc_private.id
}

resource "aws_route_table_association" "my_vpc_us_west_2c_private" {
    subnet_id = aws_subnet.private_us_west_2c.id
    route_table_id = aws_route_table.my_vpc_private.id
}

resource "aws_route_table_association" "my_vpc_us_west_2d_private" {
    subnet_id = aws_subnet.private_us_west_2d.id
    route_table_id = aws_route_table.my_vpc_private.id
}


resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP inbound connections"
  vpc_id = aws_vpc.demo_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Allow HTTP Security Group"
  }
}


resource "aws_instance" "app_server" {
  ami           = "ami-0b28dfc7adc325ef4"
  instance_type = "t2.micro"
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 20
  }
  subnet_id     = aws_subnet.private_us_west_2b.id
  vpc_security_group_ids = [aws_security_group.allow_http.id]
  associate_public_ip_address = true

  user_data = <<USER_DATA
#!/bin/bash
yum update
yum -y install nginx
echo "$(curl http://169.254.169.254/latest/meta-data/local-ipv4)" > /usr/share/nginx/html/index.html
chkconfig nginx on
service nginx /start
  USER_DATA

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "ExampleAppServerInstance"
  }
}

resource "aws_launch_configuration" "web" {
  name_prefix = "web-"

  image_id = "ami-0b28dfc7adc325ef4" # Amazon Linux 2 AMI (HVM), SSD Volume Type
  instance_type = "t2.micro"

  security_groups = [ aws_security_group.allow_http.id ]
  associate_public_ip_address = true

  user_data = <<USER_DATA
#!/bin/bash
yum update
yum -y install nginx
echo "$(curl http://169.254.169.254/latest/meta-data/local-ipv4)" > /usr/share/nginx/html/index.html
chkconfig nginx on
service nginx start
  USER_DATA

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "elb_http" {
  name        = "elb_http"
  description = "Allow HTTP traffic to instances through Elastic Load Balancer"
  vpc_id = aws_vpc.demo_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Allow HTTP through ELB Security Group"
  }
}

resource "aws_elb" "web_elb" {
  name = "web-elb"
  security_groups = [
    aws_security_group.elb_http.id
  ]
  subnets = [
    aws_subnet.private_us_west_2c.id,
    aws_subnet.private_us_west_2d.id
  ]

  cross_zone_load_balancing   = true

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "HTTP:80/"
  }

  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "80"
    instance_protocol = "http"
  }

}

resource "aws_autoscaling_group" "web" {
  name = "${aws_launch_configuration.web.name}-asg"

  min_size             = 1
  desired_capacity     = 2
  max_size             = 4

  health_check_type    = "ELB"
  load_balancers = [
    aws_elb.web_elb.id
  ]

  launch_configuration = aws_launch_configuration.web.name

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  metrics_granularity = "1Minute"

  vpc_zone_identifier  = [
    aws_subnet.private_us_west_2c.id,
    aws_subnet.private_us_west_2d.id
  ]

  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "web"
    propagate_at_launch = true
  }

}

resource "aws_autoscaling_policy" "web_policy_up" {
  name = "web_policy_up"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}

resource "aws_cloudwatch_metric_alarm" "web_cpu_alarm_up" {
  alarm_name = "web_cpu_alarm_up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "60"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  alarm_description = "This metric monitor EC2 instance CPU utilization"
  alarm_actions = [ aws_autoscaling_policy.web_policy_up.arn ]
}

resource "aws_autoscaling_policy" "web_policy_down" {
  name = "web_policy_down"
  scaling_adjustment = -1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}

resource "aws_cloudwatch_metric_alarm" "web_cpu_alarm_down" {
  alarm_name = "web_cpu_alarm_down"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "10"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  alarm_description = "This metric monitor EC2 instance CPU utilization"
  alarm_actions = [ aws_autoscaling_policy.web_policy_down.arn ]
}

output "elb_dns_name" {
  value = aws_elb.web_elb.dns_name
}

resource "aws_s3_bucket" "demo123456789" {
    bucket = "demo123456789"
}
