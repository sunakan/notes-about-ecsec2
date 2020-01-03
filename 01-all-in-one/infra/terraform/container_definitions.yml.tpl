---
# - essential
#   - bool
#   - タスク実行に必要かどうか
#   - このコンテナが何らかの理由で停止した時、他のコンテナも止めるかどうか
# - memoryReservation
#   - number
#   - コンテナ用に予約するメモリの制限の指定

-
  name: suna-app
  cpu: 256
  memory: 512
  image: ${image}
  essential: true
  retention_in_days: 1
  portMappings:
    -
      protocol: tcp
      containerPort: ${port}
  logConfiguration:
    logDriver: awslogs
    options:
      awslogs-group: ${awslog_group}
      awslogs-region: ap-northeast-1
      awslogs-stream-prefix: hogesuna
