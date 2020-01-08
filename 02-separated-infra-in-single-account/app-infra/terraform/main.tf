locals {
  app_port     = 4567
  nginx_port   = 80
  awslog_group = "/ecs/suna-cluster/sunatra"
  environment  = "production"
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
# コンテナ定義モジュール
################################################################################
module "app_container_definition" {
  source          = "cloudposse/ecs-container-definition/aws"
  version         = "0.21.0"
  container_image = "${aws_ecr_repository.app.repository_url}:${local.environment}"
  container_name  = "suna-app"
  environment = [
    {
      name  = "ENV"
      value = local.environment
    },
  ]
  log_configuration = {
    logDriver = "awslogs",
    options = {
      awslogs-group         = local.awslog_group,
      awslogs-region        = "ap-northeast-1",
      awslogs-stream-prefix = "hogesuna",
    },
    secretOptions = [],
  }
  secrets = [
    {
      name  = "SECRET"
      valueFrom = "BARETARAYABAI"
    },
  ]
  port_mappings = [
    {
      hostPort      = local.app_port,
      containerPort = local.app_port,
      protocol      = "tcp",
    },
  ]
}
module "nginx_container_definition" {
  source          = "cloudposse/ecs-container-definition/aws"
  version         = "0.21.0"
  container_image = "${aws_ecr_repository.nginx_sidecar.repository_url}:${local.environment}"
  container_name  = "nginx-sidecar"
  environment = [
    {
      name  = "NGINX_PORT"
      value = local.nginx_port
    },
    {
      name  = "NGINX_LOCATION"
      value = "aabbcc"
    },
    {
      name  = "APP_HOST"
      value = "127.0.0.1"
    },
    {
      name  = "APP_PORT"
      value = local.app_port
    },
  ]
  log_configuration = {
    logDriver = "awslogs",
    options = {
      awslogs-group         = local.awslog_group,
      awslogs-region        = "ap-northeast-1",
      awslogs-stream-prefix = "hogesuna",
    },
    secretOptions = [],
  }
  port_mappings = [
    {
      hostPort      = local.nginx_port,
      containerPort = local.nginx_port,
      protocol      = "tcp",
    },
  ]
  secrets = []
}

################################################################################
# タスク定義（サービスで利用される）
################################################################################
resource "aws_ecs_task_definition" "this" {
  family                   = "suna-task"
  cpu                      = "1024"
  memory                   = "1024"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  container_definitions    = "[${module.app_container_definition.json_map}, ${module.nginx_container_definition.json_map}]"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
}
################################################################################
# ターゲットグループ（後々ECSサービスとつながる）
################################################################################
resource "aws_lb_target_group" "this" {
  name                 = "suna-tg"
  target_type          = "ip"
  vpc_id               = data.terraform_remote_state.shared_infra.outputs.vpc_id
  port                 = local.nginx_port
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
# - 注意:もしターゲットグループを一度destroy/create(=replace)する時
#   - こいつが原因で失敗する
################################################################################
resource "aws_lb_listener_rule" "this" {
  listener_arn = data.terraform_remote_state.shared_infra.outputs.lb_listener_arn
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
  condition {
    path_pattern {
      values = ["/aabbcc/*"]
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
  desired_count                     = 2
  launch_type                       = "EC2"
  health_check_grace_period_seconds = 60
  network_configuration {
    assign_public_ip = false
    security_groups = [
      aws_security_group.ecs_service_sg.id,
    ]
    subnets = data.terraform_remote_state.shared_infra.outputs.public_subnet_ids
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "nginx-sidecar"
    container_port   = local.nginx_port
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
resource "aws_ecr_repository" "app" {
  name                 = "sunatra"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
resource "aws_ecr_repository" "nginx_sidecar" {
  name                 = "nginx-sidecar"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

################################################################################
# EC2用のIAM roleとinstance profile
################################################################################
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "ecs_ec2_instance_role" {
  name               = "suna-ecs-ec2-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}
data "aws_iam_policy_document" "ecs_ec2_instance_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ecs:CreateCluster",
      "ecs:DeregisterContainerInstance",
      "ecs:DiscoverPollEndpoint",
      "ecs:Poll",
      "ecs:RegisterContainerInstance",
      "ecs:StartTelemetrySession",
      "ecs:UpdateContainerInstancesState",
      "ecs:Submit*",
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
}
resource "aws_iam_policy" "ecs_ec2_instance_policy" {
  name        = "ecs_ec2_instance_policy"
  path        = "/"
  description = "ECS(EC2) instance policy"
  policy      = data.aws_iam_policy_document.ecs_ec2_instance_policy.json
}
resource "aws_iam_role_policy_attachment" "attach_ecs_ec2_instance_policy_to_role" {
  role       = aws_iam_role.ecs_ec2_instance_role.name
  policy_arn = aws_iam_policy.ecs_ec2_instance_policy.arn
}
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ecs_ec2_instance_role.name
}

################################################################################
# EC2用のセキュリティグループ
################################################################################
resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "security group for web"
  vpc_id      = data.terraform_remote_state.shared_infra.outputs.vpc_id
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
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "sg for web"
  }
}
################################################################################
# EC2用のネットワークインターフェース
################################################################################
resource "aws_network_interface" "ni_1" {
  subnet_id = data.terraform_remote_state.shared_infra.outputs.public_subnet_ids[0]
  tags = {
    Name = "ネットワークインターフェース-1"
  }
  security_groups = [
    aws_security_group.web_sg.id,
  ]
}
resource "aws_network_interface" "ni_2" {
  subnet_id = data.terraform_remote_state.shared_infra.outputs.public_subnet_ids[1]
  tags = {
    Name = "ネットワークインターフェース-2"
  }
  security_groups = [
    aws_security_group.web_sg.id,
  ]
}
################################################################################
# EC2インスタンス
################################################################################
locals {
  # Amazon ECS-Optimized Amazon Linux 2
  ami_owner       = "amazon"
  ami_name_filter = "amzn2-ami-ecs-hvm-*-x86_64-ebs"
  # Amazon Linux 2
  #ami_owner       = "amazon"
  #ami_name_filter = "amzn-ami-hvm-*-x86_64-gp2"
  # Ubuntu 18.04
  #ami_owner        = "099720109477"
  #ami_name_filter  = "ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"
}
data "aws_ami" "image" {
  most_recent = true
  owners      = [local.ami_owner]
  filter {
    name   = "name"
    values = [local.ami_name_filter]
  }
}
#resource "aws_key_pair" "auth" {
#  key_name   = "hogehoge-pubkey"
#  public_key = file("./hogehoge.pub")
#}
resource "aws_instance" "instance_1" {
  ami                  = data.aws_ami.image.id
  instance_type        = "t2.small"
  tenancy              = "default"
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  #key_name      = aws_key_pair.auth.id
  user_data = templatefile(
    "./user_data.sh.tpl",
    { cluseter_name = aws_ecs_cluster.this.name }
  )
  root_block_device {
    volume_type = "gp2"
    volume_size = 30
  }
  network_interface {
    network_interface_id = aws_network_interface.ni_1.id
    device_index         = 0
  }
  tags = {
    Name = "instance-1"
  }
}
resource "aws_instance" "instance_2" {
  ami                  = data.aws_ami.image.id
  instance_type        = "t2.small"
  tenancy              = "default"
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  user_data = templatefile(
    "./user_data.sh.tpl",
    { cluseter_name = aws_ecs_cluster.this.name }
  )
  root_block_device {
    volume_type = "gp2"
    volume_size = 30
  }
  network_interface {
    network_interface_id = aws_network_interface.ni_2.id
    device_index         = 0
  }
  tags = {
    Name = "instance-2"
  }
}
