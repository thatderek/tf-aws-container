import boto3, json
import zipfile, tarfile
import os, shutil, time
from botocore.exceptions import ClientError

ecr = boto3.client('ecr')
s3 = boto3.client('s3')
ecs = boto3.client('ecs')

def container_exists(ecr_name, tag):
    """ A function for searching for a container image in ECR

    This function returns a bool and a reponse object describing the result of
    a search of ECR for a container image with a specific tag in ECR. It
    returns a tuple of a bool  describing if the image was found and a response
    object from the AWS api.
    """
    print('container_exists() is checking on: ', ecr_name, tag)
    try:
        response = ecr.describe_images(
            repositoryName = ecr_name,
            imageIds = [
                {
                    'imageTag': tag
                }
            ]
        )
    except ClientError as error:
        print("container_exists() had an error: " , error)
        return False, error.response['Error']['Code']

    print("container_exists() reponse: ", response)

    if len(response['imageDetails']) == 0:
        print("container_exists() called worked but returned 0 results: ",
              response)
        return False, "The search worked but didn't turn up a container."

    print('container_exists() found the container: ', ecr_name, tag)
    return True, response


def move_code(s3_bucket, code_location):
    """Move a file in s3 from a .zip to .tar.gz

    As the time of writing, the archive-provider for terraform doesn't allow
    for archival in tar.gz format, only in the .zip format.

    https://github.com/hashicorp/terraform-provider-archive/pull/277#issuecomment-2073420171

    Currently, it looks like development has halted on this provider. However,
    kaniko requires a build context using s3 to be in a .tar.gz format:

    https://github.com/GoogleContainerTools/kaniko/blob/main/README.md#kaniko-build-contexts

    So, this function is a bit of a patch fix to make that tar.gz available for
    the kaniko runner in ECS.

    It's output will be a tuple of a bool (describing whether the operation was
    succesful) and --when successful-- the s3 file location.
    """

    print('move_code() is starting for: ', s3_bucket, code_location)

    # Build strings representing where we will do our archival work
    zip_location = '/tmp/' + code_location
    tar_file = code_location.rstrip('.zip') + '.tar.gz'
    tar_location = '/tmp/' + tar_file

    # Downloads the file
    with open(zip_location, 'wb') as f:
        s3.download_fileobj(s3_bucket, code_location, f)

    # Unzip the contents to a specific location
    with zipfile.ZipFile(zip_location, 'r') as zip_ref:
        tmp_dir = os.path.dirname(tar_location)
        os.makedirs(tmp_dir, exist_ok=True)
        zip_ref.extractall(tmp_dir)


    # For each file, add it to the tar.gz
    with tarfile.open(tar_location, mode='w:gz') as tar_ref:
        for root, dirs, files in os.walk(tmp_dir):
            for file in files:
                full_path = os.path.join(root, file)
                tar_ref.add(full_path, arcname=os.path.relpath(full_path,
                                                               tmp_dir))

    # Upload the .tar.gz to s3
    try:
        response = s3.upload_file(tar_location, s3_bucket, tar_file)
    except ClientError as e:
        print('move_code() ClientError: ', e)
        return False, e

    # If everything worked, return true and the location of the tar-file in s3
    print('move_code() success')
    return True, 's3://'+s3_bucket+'/'+tar_file


def run_build_task(task_definition_arn, cluster_name, subnet_id, security_group_id,
                    s3_code_path, repository_uri, image_tag, image_tags_additional):
    """ Runs the kaniko task in ECS

    This function instructs ECS to run the Kaniko task building our container.
    """

    # Build command parameter
    command = [
        '--context',
        s3_code_path,
        '--destination',
        repository_uri + ':'  + image_tag
    ]
    for tag in image_tags_additional:
        command.extend([
            '--destination',
            repository_uri + ':' + tag
        ])

    print('run_build_task() starting')
    try:
        response = ecs.run_task(
            taskDefinition = task_definition_arn,
            cluster = cluster_name,
            count = 1,
            launchType = 'FARGATE',
            networkConfiguration ={
                'awsvpcConfiguration': {
                    'subnets': [subnet_id],
                    'securityGroups':  [security_group_id],
                    'assignPublicIp': "ENABLED",
                },
            },
            overrides = {
                'containerOverrides': [
                    {
                        'name': 'kaniko',
                        'command': command,
                    },
                ]
            }
        )
    except ClientError as e:
        print('run_task() ClientError: ', e)
        return False, e

    task_arn = response['tasks'][0]['taskArn']

    print('run_task() success: ', task_arn)
    return True, task_arn


def container_waiter(task_arn, cluster_name, repository_name, image_tag, context):
    """
    Waits for a container with a tag to show up in ECR

    This function queries an ECS task for completion and then when that is
    done, queires an ECR repository for the existance of an image with a
    specific tag. Returns true if it shows up before the lambda runs out of
    time and false if otherwise.
    """

    print('container_waiter() started')
    i = 0

    # Wait until exeuction time remaining gets below 10 seconds (in
    # milliseconds), loop infinitely
    while context.get_remaining_time_in_millis() > 10000:
        print("container_waiter() sleeping to start loop: ", i)
        i += 1

        # This is at the top to give ECS a fighting chance to start the task
        # before we start querying it.
        time.sleep(3)

        # Get task information
        resp = ecs.describe_tasks(
            cluster = cluster_name,
            tasks = [
                task_arn,
            ]
        )

        # If no tasks are described, restart the loop
        if len(resp['tasks']) == 0:
            print('container_waiter() empty response on task_arn, looping')
            continue

        # If the status of the task doesn't appear to be stopping or stopped,
        # loop
        status = resp['tasks'][0]['lastStatus']
        if status not in [
            'DEACTIVATING',
            'STOPPING',
            'DEPROVISIONING',
            'STOPPPED',
            'DELETED'
        ]:
            print('container_waiter() status not ending/ed, looping: ', status)
            continue

        # Get image information seeing if a response shows up, continuing the
        # loop if it doesn't
        container_exists_result = container_exists(repository_name, image_tag)
        if container_exists_result[0] == True:
            print('conatiner_waiter() success!')
            return True, ""

    # If we've exted the loop, the image hasn't shown up in the allotted time.
    error = ('The image hasn\'t shown up in the allotted time. Check to see if'+
    'the lambda needs to be extended or if the container build errored.')
    print('container_waiter() failure: ' + error)
    return False, error


def lambda_handler(event, context):
    """
    The main controller invoked by lambda to build containers!

    This handler is invoked by lambda to build containers in ECS using Kaniko.
    It takes an event with the keys specified immediately below and an AWS
    Context object with a get_remaining_time_in_millis() function.
    """

    print('lambda_controller started.')
    print('event payload: ', json.dumps(event))

    # Gather info from invocation payload
    repository_name = event['repo_name']
    repository_uri = event['repository_uri']
    image_tag = event['image_tag']
    image_tags_additional = event['image_tags_additional']
    image_destination = repository_uri + ':' + image_tag

    s3_bucket = event['s3_bucket']
    # Location of the zip archive as passed from terraform -> s3
    code_location = event['code_location']

    task_definition_arn = event['task_definition_arn']
    cluster_name = event['cluster_name']
    subnet_id = event['subnet_id']
    security_group_id = event['security_group_id']


    # Quick check to see if the container already exists before building it
    container_exists_result = container_exists(repository_name, image_tag)
    if container_exists_result[0] == True:
        container = container_exists_result[1]['imageDetails'][0]
        print("Container found before building, so exiting cleanly.")
        return {
            'statusCode': 200,
            'repositoryName': container['repositoryName'],
            'imageTag': container['imageTags'][0],
            'imageDigest': container['imageDigest'],
        }

    # Get zip archive from S3 and remake it into a .tar.gz that kaiko can use
    move_code_result = move_code(s3_bucket, code_location)
    if move_code_result[0] == False:
        raise Exception("Error moving code: {}".format(move_code_result[1]))
    s3_tar_path = move_code_result[1]

    # Run the Kaniko task definition in ECS
    run_build_task_result = run_build_task(
        task_definition_arn, cluster_name, subnet_id, security_group_id,
        s3_tar_path, repository_uri, image_tag, image_tags_additional
    )
    if run_build_task_result[0] == False:
        raise Exception("Error running task to build container: {}".format(
            run_build_task_result[1])
        )

    # Grab the task arn / id 
    task_arn = run_build_task_result[1]

    # Watch the task for completion before the lambda exits
    container_waiter_result = container_waiter(
        task_arn, cluster_name, repository_name, image_tag, context
    )

    if container_waiter_result[0] == False:
        print("Error getting container details: ", container_waiter_result[1])
        # Intentionally continuing to check to for the container anyways so not
        # exiting script.

    # Check to see the container details exist in the ECR Repository
    container_exists_result = container_exists(repository_name, image_tag)
    if container_exists_result[0] == False:
        raise Exception("Contianer_exists check failed: {}".format(
            container_exists_result[1])
        )

    print("Container found. Exiting cleanly! („• ֊ •„)")
    container = container_exists_result[1]['imageDetails'][0]
    return {
        'statusCode': 200,
        'repositoryName': container['repositoryName'],
        'imageTag': container['imageTags'][0],
        'imageDigest': container['imageDigest'],
    }

if __name__ == "__main__":
    """
    This is a helper function that works when the script is invoked directly
    (as might be done in local development). It is expected lambda will execute
    the script via the lambda_handler function above, but when invoked locally,
    (with the environment variables sets below -- and with a set of matching
    AWS credentials available to the SDK's auth chain) that this script can be
    run to test it's functionality without having to deploy it to lambda for
    execution.
    """

    # These must be set in the environment when executing this script locally
    repo_name = os.getenv('REPO_NAME')
    s3_bucket = os.getenv('S3_BUCKET')
    cluster_name = os.getenv('CLUSTER_NAME')
    task_arn = os.getenv('TASK_ARN')
    image_tag = os.getenv('IMAGE_TAG')
    repository_uri = os.getenv('REPOSITORY_URI')
    code_location = os.getenv('CODE_LOCATION')
    subnet_id = os.getenv('SUBNET_ID')
    security_group_id = os.getenv('SECURITY_GROUP_ID')

    event = """
{
  "repo_name": "{}",
  "s3_bucket": "{}",
  "cluster_name": "{}",
  "task_arn":
      "{}",
  "image_tag": "{}",
  "repository_uri": "{}",
  "code_location": "{}",
  "subnet_id": "{}",
  "security_group_id": "{}",
  "key2": "value2",
  "tf": {
    "action": "create",
    "prev_input": {
      "key1": "value1",
      "key2": "value2"
    }
  }
}
""".format(repo_name, s3_bucket, cluster_name, task_arn, image_tag,
           repository_uri, code_location, subnet_id, security_group_id)

    # This creates a very limited version of the AWS Lambda conext object
    # https://docs.aws.amazon.com/lambda/latest/dg/python-context.html
    # meant solely to replicate the get_remaining_time_in_millis() function
    class Context(object):
        def __init__(self):
            self.time_start= time.time()
            self.total_duration = 5 # seconds
            self.time_end = time.time() + self.total_duration
            print("Context init, current time: ", time.time())
            print("Context init, end time: ", self.time_end)
        def get_remaining_time_in_millis(self):
            return round((self.time_end - time.time()) * 1000, 2)

    context = Context()
    event = json.loads(event)
    print(lambda_handler(event, context))
