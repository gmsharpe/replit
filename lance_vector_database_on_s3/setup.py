import boto3
import json
from botocore.exceptions import ClientError


def setup_cloud_resources(bucket_name, project_id_suffix, region='us-east-1', ):
    """
    Create the S3 bucket, IAM policy, and IAM role needed for LanceDB.
    @param bucket_name: The name of the S3 bucket to create.
    @param region: The AWS region to create the resources in. If None, the default region is used.
    :return:
    """
    policy_name = 'LanceDBS3AccessPolicy' + project_id_suffix
    role_name = 'LanceDBS3AccessRole' + project_id_suffix

    # Initialize Boto3 clients
    s3 = boto3.client('s3', region_name=region)
    iam = boto3.client('iam', region_name=region)
    sts_client = boto3.client('sts', region_name=region)

    # Use STS to get caller identity
    caller_identity = sts_client.get_caller_identity()
    arn = caller_identity['Arn']
    account_id = caller_identity.get('Account')
    policy_arn = f'arn:aws:iam::{account_id}:policy/{policy_name}'

    # Extract the user from the ARN of the 'caller_identity'
    # The user is the identity weilding the credentials for creating these
    #   resources We'll use this to define a policy allowing the user to
    #   assume a more limited role when running our implementation
    if ':user/' in arn:
        user = arn.split('/')[-1]
    elif ':assumed-role/' in arn:
        user = arn.split('/')[-1]
    else:
        user = 'Unknown'

    # Check if the S3 bucket exists
    try:
        s3.head_bucket(Bucket=bucket_name)
        print(f"Bucket '{bucket_name}' already exists.")
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == '404':
            # Bucket does not exist, create it
            s3.create_bucket(
                Bucket=bucket_name,
                CreateBucketConfiguration={'LocationConstraint': region}
            )
            print(f"Bucket '{bucket_name}' created.")
        else:
            print(f"Error checking bucket: {e}")
            raise

    # Check if the IAM policy exists
    try:
        iam.get_policy(PolicyArn=policy_arn)
        print(f"Policy '{policy_name}' already exists.")
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'NoSuchEntity':
            # Policy does not exist, create it
            policy_document = {
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": [
                            "s3:ListBucket",
                            "s3:GetObject",
                            "s3:PutObject",
                            "s3:DeleteObject"
                        ],
                        "Resource": [
                            f"arn:aws:s3:::{bucket_name}",
                            f"arn:aws:s3:::{bucket_name}/*"
                        ]
                    }
                ]
            }
            iam.create_policy(
                PolicyName=policy_name,
                PolicyDocument=json.dumps(policy_document)
            )
            print(f"Policy '{policy_name}' created.")
        else:
            print(f"Error checking policy: {e}")
            raise

    # Check if the IAM role exists
    try:
        iam.get_role(RoleName=role_name)
        print(f"Role '{role_name}' already exists.")
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'NoSuchEntity':
            # Role does not exist, create it
            assume_role_policy_document = {
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "AWS": f"arn:aws:iam::{account_id}:user/{user}"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }
            iam.create_role(
                RoleName=role_name,
                AssumeRolePolicyDocument=json.dumps(assume_role_policy_document)
            )
            print(f"Role '{role_name}' created.")
        else:
            print(f"Error checking role: {e}")
            raise

    # Attach the policy to the role
    try:
        iam.attach_role_policy(
            RoleName=role_name,
            PolicyArn=policy_arn
        )
        print(f"Policy '{policy_name}' attached to role '{role_name}'.")
    except ClientError as e:
        print(f"Error attaching policy to role: {e}")
        raise


def assume_limited_role(role_name, region='us-east-1'):
    """
        Assume a role with limited permissions to interact with the S3 bucket.

    :return: Temporary credentials for the assumed role.
    """
    sts_client = boto3.client('sts', region_name=region)
    caller_identity = sts_client.get_caller_identity()
    account_id = caller_identity.get('Account')

    try:
        assumed_role_object = sts_client.assume_role(
            RoleArn=f'arn:aws:iam::{account_id}:role/{role_name}',
            RoleSessionName='LanceDBSession'
        )
        credentials = assumed_role_object['Credentials']
        print("Assumed role and obtained temporary credentials.")
    except ClientError as e:
        print(f"Error assuming role: {e}")
        raise

    return credentials




def destroy(bucket_name, policy_name, role_name, region='us-east-1'):

    # Initialize Boto3 clients
    s3 = boto3.client('s3', region_name=region)
    iam = boto3.client('iam', region_name=region)
    sts_client = boto3.client('sts', region_name=region)
    account_id = sts_client.get_caller_identity().get('Account')
    policy_arn = f'arn:aws:iam::{account_id}:policy/{policy_name}'
    # Detach and delete the IAM policy
    try:
        # Detach the policy from all roles
        attached_roles = iam.list_entities_for_policy(PolicyArn=policy_arn)['PolicyRoles']
        for role in attached_roles:
            iam.detach_role_policy(RoleName=role['RoleName'], PolicyArn=policy_arn)
            print(f"Detached policy '{policy_name}' from role '{role['RoleName']}'.")

        # Delete all policy versions
        policy_versions = iam.list_policy_versions(PolicyArn=policy_arn)['Versions']
        for version in policy_versions:
            if not version['IsDefaultVersion']:
                iam.delete_policy_version(PolicyArn=policy_arn, VersionId=version['VersionId'])
                print(f"Deleted policy version '{version['VersionId']}' for policy '{policy_name}'.")

        # Delete the policy
        iam.delete_policy(PolicyArn=policy_arn)
        print(f"Deleted policy '{policy_name}'.")
    except ClientError as e:
        if e.response['Error']['Code'] == 'NoSuchEntity':
            print(f"Policy '{policy_name}' does not exist.")
        else:
            print(f"Error deleting policy: {e}")
            return

    # Detach policies and delete the IAM role
    try:
        # Detach all managed policies from the role
        attached_policies = iam.list_attached_role_policies(RoleName=role_name)['AttachedPolicies']
        for policy in attached_policies:
            iam.detach_role_policy(RoleName=role_name, PolicyArn=policy['PolicyArn'])
            print(f"Detached policy '{policy['PolicyName']}' from role '{role_name}'.")

        # Delete all inline policies
        inline_policies = iam.list_role_policies(RoleName=role_name)['PolicyNames']
        for policy in inline_policies:
            iam.delete_role_policy(RoleName=role_name, PolicyName=policy)
            print(f"Deleted inline policy '{policy}' from role '{role_name}'.")

        # Delete the role
        iam.delete_role(RoleName=role_name)
        print(f"Deleted role '{role_name}'.")
    except ClientError as e:
        if e.response['Error']['Code'] == 'NoSuchEntity':
            print(f"Role '{role_name}' does not exist.")
        else:
            print(f"Error deleting role: {e}")
            return

    # Delete all objects and the S3 bucket
    try:
        # List and delete all objects in the bucket
        objects = s3.list_objects_v2(Bucket=bucket_name)
        if 'Contents' in objects:
            for obj in objects['Contents']:
                s3.delete_object(Bucket=bucket_name, Key=obj['Key'])
                print(f"Deleted object '{obj['Key']}' from bucket '{bucket_name}'.")

        # Delete the bucket policy
        try:
            s3.delete_bucket_policy(Bucket=bucket_name)
            print(f"Deleted policy for bucket '{bucket_name}'.")
        except ClientError as e:
            if e.response['Error']['Code'] == 'NoSuchBucketPolicy':
                print(f"No policy found for bucket '{bucket_name}'.")
            else:
                print(f"Error deleting bucket policy: {e}")
                return

        # Delete the bucket
        s3.delete_bucket(Bucket=bucket_name)
        print(f"Deleted bucket '{bucket_name}'.")
    except ClientError as e:
        if e.response['Error']['Code'] == 'NoSuchBucket':
            print(f"Bucket '{bucket_name}' does not exist.")
        else:
            print(f"Error deleting bucket: {e}")
            return