locals {
  port         = 4567
  awslog_group = "/ecs/suna-cluster/sunatra"
}
################################################################################
# 共有tfstateからoutputsを取得
################################################################################
data "terraform_remote_state" "shared_infra" {
  backend = "s3"
  config = {
    bucket  = "foobar-shared-infra"
    key     = "02-separated-infra-in-single-account/terraform.tfstate"
    region  = "ap-northeast-1"
    profile = var.target_aws_account_profile
  }
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
  vpc_id               = data.terraform_remote_state.shared_infra.outputs.vpc_id
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
# リスナールール（ALBのリスナーとターゲットグループを結ぶ）
#   - 外部情報(remote_state)としてALBのリスナーのarnが必須
#   - ALBが外部情報となっている理由
#     - アプリ毎にALBを立てるとお金がかかるから
################################################################################
resource "aws_lb_listener_rule" "this" {
  listener_arn = data.terraform_remote_state.shared_infra.outputs.lb_listener_arn
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
  condition {
    path_pattern {
      values = ["/*"]
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
  vpc_id      = data.terraform_remote_state.shared_infra.outputs.vpc_id
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
    subnets = data.terraform_remote_state.shared_infra.outputs.public_subnet_ids
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
