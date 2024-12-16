variable container_port {
  description = "Port for Docker host and container"
  type = string
  default = 80
}

variable cpu {
  description = "CPU of Fargate Task. Make sure you put valid Memory and CPU pair, refer: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ecs-taskdefinition.html#cfn-ecs-taskdefinition-cpu:~:text=requires%3A%20Replacement-,Cpu,-The%20number%20of"
  type = string
  default = 512
}

variable memory {
  description = "Memory of Fargate Task.  Make sure you put valid Memory and CPU pair, refer: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ecs-taskdefinition.html#cfn-ecs-taskdefinition-cpu:~:text=requires%3A%20Replacement-,Cpu,-The%20number%20of"
  type = string
  default = 1024
}

variable environment_name {
  description = "Unique name to distinguish different web application in the same AWS account (min length 1 and max length 4)"
  type = string
  default = "dev"
}

variable desired_task_count {
  description = "Desired Docker task count"
  type = string
  default = 1
}

variable min_containers {
  description = "Minimum containers for Autoscaling. Should be less than or equal to DesiredTaskCount"
  type = string
  default = 1
}

variable max_containers {
  description = "Maximum containers for Autoscaling. Should be greater than or equal to DesiredTaskCount"
  type = string
  default = 3
}

variable auto_scaling_target_value {
  description = "CPU Utilization Target"
  type = string
  default = 80
}

variable s3_data_prefix_kb {
  description = "S3 object prefix where the knowledge base source documents should be stored"
  type = string
  default = "knowledge_base"
}

variable cognito_user_pool_id {
  description = "Cognito User Pool Id.Must be a valid Cognito User Pool ID. For example: us-east-1_abcdefgh"
  type = string
}

variable cognito_app_client_id {
  description = "Cognito Application Client Id.Must be valid consisting of lowercase letters and numbers"
  type = string
}