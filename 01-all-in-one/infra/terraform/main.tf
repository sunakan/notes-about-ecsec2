locals {
  port         = 4567
  awslog_group = "/ecs/suna-cluster/sunatra"
}
################################################################################
# VPC
################################################################################
resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  tags = {
    Name = "VPC領域"
  }
}
################################################################################
# インターネットゲートウェイ
################################################################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "VPC領域のIGW"
  }
}
################################################################################
# ルートテーブル
################################################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "pub-route-table"
  }
}
################################################################################
# サブネット
#   - サブネットマスク:20
#     - 00001010 00000000 0000|0000 00000000 = 10.0.0.0/20
#     - 最初の16bitは動かせない(vpc定義時に)
#     - よって第3オクテットの左の4bit分がサブネットの最大数=16個
#     - 0000(=0),0001(=16),0010(=32),...
################################################################################
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.0.0/20"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1a"
  tags = {
    Name = "pub-subnet-1-tokyo1a"
  }
}
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.16.0/20"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1c"
  tags = {
    Name = "pub-subnet-2-tokyo1c"
  }
}
resource "aws_route_table_association" "associate_routetable_to_subnet_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "associate_routetable_to_subnet_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

################################################################################
# ALB用のセキュリティグループ
################################################################################
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "security group for web"
  vpc_id      = aws_vpc.this.id
  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
  ingress {
    from_port = 4567
    to_port   = 4567
    protocol  = "tcp"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "sg for alb"
  }
}
###############################################################################
# ALB
###############################################################################
resource "aws_lb" "this" {
  name                       = "suna-alb"
  load_balancer_type         = "application"
  internal                   = false
  idle_timeout               = 60
  enable_deletion_protection = false
  subnets = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id,
  ]
  access_logs {
    bucket  = ""
    enabled = false
  }
  security_groups = [
    aws_security_group.alb_sg.id,
  ]
}

################################################################################
# ロギング用CloudWatchのグループを作成
################################################################################
resource "aws_cloudwatch_log_group" "this" {
  name              = local.awslog_group
  retention_in_days = 1
}
################################################################################
# ECSクラスタ                           リスナールール---リスナー---ALB
#    \_ECSサービス---ターゲットグループ_/
#         \_タスク定義(1コンテナ定義を1タスクとした時の必要なマシンリソース等)
#              \_コンテナ定義(コンテナの組み合わせ)
################################################################################
resource "aws_ecs_cluster" "this" {
  name = "suna-cluster"
}
################################################################################
# タスク定義（サービスで利用される）
# - タスクで実行するコンテナ定義は別ファイルで定義
################################################################################
resource "aws_ecs_task_definition" "this" {
  family                   = "suna-task"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  container_definitions = jsonencode(yamldecode(templatefile(
    "./container_definitions.yml.tpl",
    {
      image        = "${aws_ecr_repository.this.repository_url}:production",
      port         = local.port,
      awslog_group = local.awslog_group,
    }
  )))
  execution_role_arn = aws_iam_role.ecs_task_execution.arn
}
################################################################################
# ターゲットグループ（後々ECSサービスとつながる）
################################################################################
resource "aws_lb_target_group" "this" {
  name                 = "suna-tg"
  target_type          = "ip"
  vpc_id               = aws_vpc.this.id
  port                 = local.port
  protocol             = "HTTP"
  deregistration_delay = 300
  health_check {
    path                = "/"
    healthy_threshold   = 5
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = 200
    port                = "traffic-port"
    protocol            = "HTTP"
  }
}

################################################################################
# Listener
#   - 全部80番portで受ける
#   - SecurityGroupRuleも楽になる
################################################################################
resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "rootにアクセスしてます"
      status_code  = 200
    }
  }
}

################################################################################
# リスナールール（ALBのリスナーとターゲットグループを結ぶ）
#   - 外部情報(remote_state)としてALBのリスナーのarnが必須
################################################################################
resource "aws_lb_listener_rule" "this" {
  listener_arn = aws_lb_listener.this.arn
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
  condition {
    path_pattern {
      values = ["/hogehoge/*"]
    }
  }
}

################################################################################
# ECSサービス（クラスタで利用される）
# - 起動するタスクの数を選択
# - 何らかの理由でタスクが終了しても自動的に新しいタスクを起動してくれる
# - ALBとの橋渡しでもある
#   - (ネットからのリクエストをALBで受け、そのリクエストをコンテナにフォワード)
################################################################################
resource "aws_security_group" "ecs_service_sg" {
  name        = "ecs service sg"
  description = "Using ECS service"
  vpc_id      = aws_vpc.this.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 4567
    to_port     = 4567
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
    Name = "sg for ecs serevice"
  }
}
resource "aws_ecs_service" "this" {
  name                              = "sunatra"
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.this.arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  platform_version                  = "1.3.0"
  health_check_grace_period_seconds = 60
  network_configuration {
    assign_public_ip = true
    security_groups = [
      aws_security_group.ecs_service_sg.id,
    ]
    subnets = [
      aws_subnet.public_1.id,
      aws_subnet.public_2.id,
    ]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "suna-app"
    container_port   = local.port
  }
  lifecycle {
    ignore_changes = [task_definition]
  }
}

################################################################################
# ECSタスク実行用のポリシーを持ったIAMロールの作成
################################################################################
data "aws_iam_policy" "ecs_task_execution_role_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
data "aws_iam_policy_document" "ecs_task_execution_principal" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
data "aws_iam_policy_document" "ecs_task_execution_identity" {
  source_json = data.aws_iam_policy.ecs_task_execution_role_policy.policy
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameters", "kms:Decrypt"]
    resources = ["*"]
  }
}
resource "aws_iam_policy" "ecs_task_execution_identity" {
  name   = "ecs-task-execution-identity"
  policy = data.aws_iam_policy_document.ecs_task_execution_identity.json
}
resource "aws_iam_role" "ecs_task_execution" {
  name               = "ecs-sunatra-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_principal.json
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.ecs_task_execution_identity.arn
}
################################################################################
# ECR
################################################################################
resource "aws_ecr_repository" "this" {
  name                 = "sunatra"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
