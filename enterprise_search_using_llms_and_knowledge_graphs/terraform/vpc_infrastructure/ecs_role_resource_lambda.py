import boto3
from botocore.exceptions import ClientError
import cfnresponse
iam_client = boto3.client('iam')

def handler(event, context):

    try:
        request_type = event['RequestType']
        print(request_type)

        if request_type == 'Create':
            desired_ecs_role_name = "AWSServiceRoleForECS"
            desired_ecs_scaling_role_name = "AWSServiceRoleForApplicationAutoScaling_ECSService"

            try:
                iam_client.get_role(RoleName=desired_ecs_role_name)
                ecs_role_exists = True
            except ClientError as e:
                if e.response['Error']['Code'] == 'NoSuchEntity':
                    ecs_role_exists = False
                else:
                    ecs_role_exists = True

            try:
                iam_client.get_role(RoleName=desired_ecs_scaling_role_name)
                ecs_scaling_role_exists = True
            except ClientError as e:
                if e.response['Error']['Code'] == 'NoSuchEntity':
                    ecs_scaling_role_exists = False
                else:
                    ecs_scaling_role_exists = True

            print(f"ECS service role exist? {ecs_role_exists}")
            if not ecs_role_exists:
                iam_client.create_service_linked_role(AWSServiceName="ecs.amazonaws.com")

            print(f"ECS scaling service role exist? {ecs_scaling_role_exists}")
            if not ecs_scaling_role_exists:
                iam_client.create_service_linked_role(AWSServiceName="ecs.application-autoscaling.amazonaws.com")
        elif request_type == 'Delete':
            try:
                vpc_id = event['ResourceProperties']['VpcId']
                ec2 = boto3.client('ec2')

                # Describe all ENIs in the VPC
                response = ec2.describe_network_interfaces(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])

                # Delete each ENI
                for eni in response['NetworkInterfaces']:
                    if not eni['Description'].startswith('AWS created network interface'):
                        try:
                            ec2.delete_network_interface(NetworkInterfaceId=eni['NetworkInterfaceId'])
                            print(f"Deleted ENI: {eni['NetworkInterfaceId']}")
                        except ec2.exceptions.ClientError as e:
                            if e.response['Error']['Code'] == 'InvalidNetworkInterfaceID.NotFound':
                                print(f"ENI {eni['NetworkInterfaceId']} not found, skipping.")
                            else:
                                print(f"Error deleting ENI {eni['NetworkInterfaceId']}: {str(e)}")

                cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            except Exception as e:
                print(f"Delete Stack Error: {str(e)}")
                cfnresponse.send(event, context, cfnresponse.FAILED, {})

    except Exception as ex:
        print(ex)
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
    else:
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})