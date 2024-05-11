# CloudFormation 101

A hands-on CloudFormation work that quickly dives into intermediate features of CloudFormation,
assuming you are already familiar with AWS VPCs and YAML formating.

A [script](solution/deploy.sh) is provided that will deploy all of the solution templates in turn, for testing,
and also delete the stacks when you are done.

## 0 - Setup

Environment
- AWS Account
- AWS CLI v2
- (Default) profile defined
- IDE like VS Code
    - Alternatively use cloud9, but this costs money to run

You should be able to run this from the terminal in your IDE:
```bash
aws sts get-caller-identity
```

## 1 - Simplest template

Create and deploy a simple VPC using CloudFormation by creating `network.yaml`, defining a VPC resource.

CloudFormation templates start with
- a format version `AWSTemplateFormatVersion: "2010-09-09"`
- optional description
- at least one resource
- comments start with a `#`

```yaml
---
AWSTemplateFormatVersion: "2010-09-09"

Description: Incrementally building a cloudformation template

Resources:

  # Define your VPC resource here
```

Each resource will have one or more properties, some properties are mandatory, others are optional. Read this documentation for the properties of a [VPC](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-vpc.html).

You can then deploy with:

```bash
STACK=cfn-network
aws cloudformation create-stack \
    --stack-name $STACK \
    --template-body file://network.yaml
```

Resources:
- [CloudFormation Resources](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/gettingstarted.templatebasics.html#gettingstarted.templatebasics.multiple)
- [AWS::EC2::VPC](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-vpc.html)
- [Solution](solution/soln-01.yaml)

## 2 - Update VPC

Add a `Name` tag to the VPC in your `network.yaml`. But what name to give your VPC?
Each CloudFormation stack must have a unique name, so using the name you gave your stack is often a good choice for at least part of your resource name.
The stack name, and other details about your stack, can be used in your template using Psuedo Parameters like `AWS::StackName`:

```yaml
Key: Name
Value: !Ref "AWS::StackName"
```

`!Ref` is an intrinsic function built into CloudFormation for refering to parameters or other resources in your template.

Update the template by running

```bash
aws cloudformation update-stack \
    --stack-name $STACK \
    --template-body file://network.yaml
```

Resources:
- [CloudFormation Pseudo Parameters](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/pseudo-parameter-reference.html)
- [!Ref](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-ref.html)
- [CloudFormation Updates](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-updating-stacks-direct.html)
- [AWS::EC2::VPC](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-vpc.html)
- [AWS::EC2::VPC tag](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ec2-vpc-tag.html)
- [Solution](solution/soln-02.yaml)

## 3 - Parameterise the VPC

Improve template reusability by [parameterising](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html) rather than hard-coding configuration values. We can still provide useful defaults with these parameters, and also perform input validation. 

For example, we could provide a 6-digit cost centre to use for resources, instead of using `AWS::StackName`
```yaml
  CostCentre:
    Type: String
    Description: Allocate the stack resources to this cost centre
    MinLength: 6
    MaxLength: 6
    AllowedPattern: ^([0-9]{6})$
    ConstraintDescription: 6-digit cost centre code
```

For our template, we can parameterise the VPC CIDR block.

When defining your parameter, set the default to a different CIDR range than you were using, for example use `10.1.0.0/16` rather than `10.0.0.0/16`.
CloudFormation can change some configurations in place, but this is not one of them.
So what will happen when you update? When you run the update, switch to the console and watch the events.

For input validation we can specify a list of allowed values, or a regex that the input should match.
Just in case you don't know this off the top of your head, here is a regex for a CIDR block:

```yaml
Default: 10.1.0.0/16
AllowedPattern: ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(1[6-9]|2[0-8]))$
```

You can then refer to the parameter value using the intrinsic function [Ref](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html#parameters-section-structure-referencing). There are different ways to specify an intrinsic function, but I recommend `!Ref` rather then `Ref:` is the most readable.

Update your template once you have made this change.

If you want to test the input validation this command (using whatever you called the CIDR parameter) should return an immediate error:

```bash
aws cloudformation update-stack \
    --stack-name $STACK \
    --template-body file://network.yaml \
    --parameters ParameterKey=VpcCidr,ParameterValue=300.300.300.300/300
```

Resources:
- [CloudFormation Parameters](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html)
- [Parameter Properties](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html)
- [References](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html#parameters-section-structure-referencing)
- [AWS::EC2::VPC](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-vpc.html)
- [Solution](solution/soln-03.yaml)

## 4 - Dependencies

The order resources are specified in the template have no impact on the order they are deployed. Instead CloudFormation uses the references in the resource properties to build a dependency graph to determine the appropriate order. This also allows it to deploy some resources in parallel. 

However, not all dependencies are explicit. Add the following resources to your `network.yaml`:

```yaml
  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
      - Key: Name
        Value: !Ref "AWS::StackName"

  GatewayAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      InternetGatewayId: !Ref InternetGateway
      VpcId: !Ref VPC

  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      Tags:
        - Key: Name
          Value: !Sub "${AWS::StackName}-public"
      VpcId: !Ref VPC

  PublicRoute:
    Type: AWS::EC2::Route
    DependsOn: GatewayAttachment
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway
```

The `PublicRoute` refers to the `InternetGateway` as the target, but this only works if the `InternetGateway` is actually attached to the VPC using the `GatewayAtteachment`. CloudFormation does not know this, so we can define a dependency using `DependsOn`. Without that dependency we have a potential race condition with this template sometimes failing to deploy.

Another use case for this might be to delay deploying an EC2 instance and its software until the database is deployed. CloudFormation has no idea about application-level dependencies.

The other property to note in this update is the use of `!Sub` rather than `!Ref` in `PublicRouteTable`. The `!Sub` substitutes a value into a string, which is especially handy when naming resources like route tables where you will likely have more than one.

Update your stack with this change.

Resources:
- [AWS::EC2::InternetGateway](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-internetgateway.html)
- [AWS::EC2::VPCGatewayAttachment](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-vpcgatewayattachment.html)
- [AWS::EC2::RouteTable](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-routetable.html)
- [AWS::EC2::Route](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-routetable.html)
- [DependsOn](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-attribute-dependson.html)
- [Sub Instrinsic Function](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-sub.html)
- [Solution](solution/soln-04.yaml)

## 5 - Networking intrinsic functions

There are more intrinsic functions to help you with networking, especially with subnets. The example below assumes a naming convention for availability zones and uses a hard coded CIDR block:

```yaml
  PublicSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Sub "${AWS::Region}a"
      CidrBlock: 10.1.0.0/24
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub "${AWS::StackName}-public-a"
```

The intrinsic functions `!Cidr` and `!GetAZs` return a list of CIDR blocks and a list of Availability Zones, respectively. You can then use `!Select` to pick from that list.

Add resources for two public subnets in different AZs with /24 CIDR blocks.

Resources:
- [AWS::EC2::Subnet](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-subnet.html)
- [!Cidr](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-cidr.html)
- [!GetAZs](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-getavailabilityzones.html)
- [!Select](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-select.html)
- [Solution](solution/soln-05.yaml)

## 6 - Cut and paste

Hopefully you have realised that we are building the template incrementally, updating with each new resource to quick confirmation that everything is defined correctly.

You should already know that the next steps are
- Associate subnets with the right route table, this will be similar to associating an internet gateway with a VPC.
- Repeat for private subnets for an application and a database tier
  - Note we do not have NAT Gateways so there is no application route just yet.

Resources:
- [AWS::EC2::Subnet](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-subnet.html)
- [AWS::EC2::SubnetRouteTableAssociation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-subnetroutetableassociation.html)
- [Solution](solution/soln-06.yaml)

## 7 - Foreach and Mappings (Optional)

With resources like subnets and route tables there is potential for a lot of repetition.
YAML does not natively support programming constructs like branches and loops, but CloudFormation has ways to do this ... with limitations.

The loop is defined as a resource with a variable and a list to iterate:

```yaml
  Fn::ForEach::MyLoop:
    - Id
    - [ Apple, Banana, Orange ]
    - ${Id}Item:
        Type: AWS::EC2::Instance
        Properties:
            ImageId: !Ref Ami
            ...
            Tags:
            - Key: Name
                Value: !Sub "${AWS::StackName}-${Id}"
```

Scroll down through this blog and you will see an example using `Fn::ForEach` in templates for subnets, including
- Adding the transform `Transform: AWS::LanguageExtensions`
- Using lists in parameters
- Loops (availability zone) within loops (tier)
- Mapping things like CIDR blocks

One of the limitations of `Fn::ForEach` is the order in which intrinsic functions are applied can complicate these definitions.
You will encounter this when trying to set the CIDR range for the templates. The blogs below suggest different approaches,
the solution provided is another approach again, with a combination of parameters and mappings.

It is left to the author to decide if the complexity of these loops is worth the lines of code saved. In this example the length of the template has barly changed.

Resources:
- [Foreach Blog](https://aws.amazon.com/blogs/devops/exploring-fnforeach-and-fnfindinmap-enhancements-in-aws-cloudformation/)
- [Another ForEach approach](https://dev.to/aws-builders/template-for-creating-a-3-layer-subnet-vpc-using-cloudformations-intrinsic-function-fnforeach-3fim)
- [Fn::ForEach](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-foreach.html)
- [Mapping](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/mappings-section-structure.html)
- [Fn::FindInMap](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-findinmap.html)
- [Template Macros and CAPABILITY_AUTO_EXPAND](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-macros.html)
- [Solution](solution/soln-07.yaml)

## 8 Outputs

Outputing resource identifiers is helpful to those who deployed a stack and to other stacks that depend on those resources.
Outputs can also be exported so they can be referred to by any templates in the same region.

Add outputs an export the VPC and subnets, exporting the subnets identifiers as lists for the public, web and databases subnets.
`!Join` is a useful intrinsic function for building a string, where you provide the separator and then the list of items like this:

```yaml
  PublicSubnetIds:
    Value: !Join [ ",", [ !Ref PublicASubnet, !Ref PublicBSubnet ] ]
```

Update the template and then you should be able to run this to see the outputs:

```bash
aws cloudformation describe-stacks \
  --stack-name cfn-network \
  --query Stacks[*].Outputs \
  --output table
```

Resources:
- [Outputs](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/outputs-section-structure.html)
- [Subnet Attributes](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-subnet.html#aws-resource-ec2-subnet-return-values)
- [!Join](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-join.html)
- [Solution](solution/soln-08.yaml)

---

## 9 - Security Group Stack

We can continue adding more resources to the template, however
- there are [limits](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cloudformation-limits.html) on the size of a template file
- as it gets larger with more and more resources it becomes harder to understand
- you may have different people/teams responsible for different components, this gets harder to coordinate with a single template

There are different strategies for how you can work with multiple templates that combine to represent a workload.
One approach is to use multiple templates and use the exports to refer to resources in other stacks. 
While this is approach reduces coupling to just the exports, there may still be implicit dependencies you have to manage.
For example, writing a script to deploy the templates in the right order.

Write a new template, `secgrp.yaml`, for the security groups, defining a security group for each tier:
- The public tier should allow HTTP traffic from the internet
- Application tier should allow HTTP traffic from the public tier
- Database tier should allow traffic on port 3306 from the application tier

Use `!ImportValue` to retrieve the VPC ID your existing stack, the name of the original stack could be a parameter.

```yaml
      VpcId:
        Fn::ImportValue:
          !Sub ${NetworkStack}-VpcId
```

Then create this new stack:

```bash
SECGRP=cfn-secgrp
aws cloudformation create-stack \
    --stack-name $SECGRP \
    --template-body file://secgrp.yaml
```

Resources:
- [CloudFormation limits](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cloudformation-limits.html)
- [AWS::EC2::SecurityGroup](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-securitygroup.html)
- [!ImportValue](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-importvalue.html)
- [Solution](solution/secgrp-01.yaml)

## 10 Conditions

Some resources in our templates may be optional depending on what parameters are set.
For example we may not want to add a rule for SSH to instances in the public subnet, or set a specific CIDR block for SSH.
By adding a parameter that is an empty string by default, but can do a CIDR block:

```yaml
  SshCidr:
    Type: String
    Default: ""
    Description: SSH CIDR or empty for no SSH access to public security group
```

We can then define a condition in the `Conditions` section of the template:

```yaml
Conditions:

  # Is SSH CIDR set?
  HasSshCidr: !Not [ !Equals [ !Ref SshCidr, "" ] ]
```

Then we define the resource we can specify the condition which must evaluate to true to provision the resource:

```yaml
  SshPublicIngress:
    Type: AWS::EC2::SecurityGroupIngress
    Condition: HasSshCidr
    Properties:
      ...
```

This update should return an error that there is nothing to update:

```bash
aws cloudformation update-stack \
    --stack-name $SECGRP \
    --template-body file://secgrp.yaml
```

Specify the SSH CIDR block to force the new ingress rule:

```bash
aws cloudformation update-stack \
    --stack-name $SECGRP \
    --template-body file://secgrp.yaml \
    --parameters ParameterKey=SshCidr,ParameterValue=0.0.0.0/0
```

Resources:
- [Conditions](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-conditions.html)
- [AWS::EC2::SecurityGroupIngress](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-securitygroupingress.html)
- [Solution](solution/secgrp-02.yaml)

---

## 11 - Nested Network Stack

Another approach to multiple stacks is to use [Nested Stacks](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-nested-stacks.html),
which works best when these templates are likely to be deployed together but in a particular order due to the dependencies between them.
A parent template is used to create multiple nested stacks using other templates preloaded in an S3 bucket that CloudFormation.
They may also nested stacks within a nested stack.

**Updates to the nested stacks should always be performed by updating the parent stack**. It will then determine which of
the child templates have changes and perform updates on those stacks. 

You will need to create a bucket and copy your template into that bucket, maybe like this:

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET=cfn-network-$ACCOUNT
aws s3 mb s3://$BUCKET
aws s3 cp network.yaml s3://$BUCKET/network.yaml
```

Create a new template, called `parent.yaml` and define a `AWS::CloudFormation::Stack` resource using your network
template in the S3 bucket. Consider passing the bucket name to the template as a paramenter.

The parent template may also output and export the outputs from the network stack. Exports can then be used
by other stacks not in this nested stack. The `!GetAtt` intrinsic function can be used to extract other properties
and return values from resources, in this case the outputs from the stack:

```yaml
  PublicSubnetIds:
    Value: !GetAtt network.Outputs.PublicSubnetIds
    Export:
      Name: !Sub "${AWS::StackName}-PublicSubnetIds"
```

You can see other attributes in the documentation for resources, for example [AWS::EC2::Subnet return values](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-subnet.html#aws-resource-ec2-subnet-return-values).

Create the parent stack to see it also create the nested stack.
If you updated the template to use `ForEach` loops in Step 7, you will need to specify the `CAPABILITY_AUTO_EXPAND` capability here too.

```bash
aws cloudformation create-stack \
  --stack-name cfn-network-nested \
  --template-body file://parent.yaml \
  --parameters ParameterKey=Bucket,ParameterValue=$BUCKET \
  --capabilities CAPABILITY_AUTO_EXPAND
```

Carefully check the events if you observe the new stacks rolling back.

Resources:
- [Nested Stacks](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-nested-stacks.html)
- [AWS::CloudFormation::Stack](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-cloudformation-stack.html)
- [!GetAtt](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-getatt.html)
- [Solution](solution/parent-01.yaml)


## 12 - Nested Security Group Stack

Now reworl the security group template to be a nested template of the parent template,
to illustrate another approach for multiple templates.

Because this is now a nested template we can rely less on importing outputs and instead pass values
in as parameters, in this example the VPC ID.

Remember to copy your security group template to the S3 bucket, and update the parent template.
You will also need to delete the previous stand-alone security stack.

Resources:
- [AWS::EC2::SecurityGroup](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-securitygroup.html)
- [Solution - Parent](solution/parent-02.yaml)
- [Solution - SecGrp](solution/secgrp-03.yaml)

---

## 13 - Application Template

***The follow steps will incur costs in your account. These can be minimised by delete the stack once complete.***

In this step you are going to deploy a linux web server in the public subnet, defined in its own template `web.yaml`.

In the past AMIs were hardcoded in the *Mapping* section of a template. AWS now provides the name of the latest AMIs
in Systems Manager Parameter Store that you can fetch as parameters to your template:

```yaml
  AmazonLinuxAMIID:
    Type: AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>
    Default: ...
```

The default value should be the parameter store path, you can obtain a list of the paths defined using this command:

```bash
aws ssm get-parameters-by-path --path "/aws/service/ami-amazon-linux-latest" --region us-east-1 --query 'Parameters[].{Name:Name}' --output text
```

We can install a website using user data:

```bash
#!/bin/bash
yum update -y
yum install -y httpd git
cd /var/www/html
git clone https://github.com/gabrielecirulli/2048.git .
systemctl start httpd
systemctl enable httpd
```

Remember to copy your web template to the S3 bucket, and update the parent template.

Resources:
- [AWS::EC2::Instance](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-instance.html)
- [Dynamic references](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/dynamic-references.html)
- [Query for the latest Amazon Linux AMI IDs using AWS Systems Manager Parameter Store](https://aws.amazon.com/blogs/compute/query-for-the-latest-amazon-linux-ami-ids-using-aws-systems-manager-parameter-store/)
- [Solution - Parent](solution/parent-03.yaml)
- [Solution - Instance](solution/web-01.yaml)

## 14 - Custom Resources (Advanced)

There may be situations where you want to create a resource that cloudformation does not directly support.
For example, we want to create an AMI from the webserver we launched, so that we can use this AMI in an
AutoScaling Group.

The SDKs support creating an AMI from an instance, so we can define a custom resource that runs a Lambda
function to do other things in our environment.

For this step you should go straight to the solution and read through the code to see what it does, this
is not something you will be able to write yourself and quickly get it right. Plus mistakes can take a long
time to complete while you wait for the customer resource to time out.

1. The EC2 instance userdata uses a signal to CloudFormation so that CloudFormation knows when the 
userdata has completed and an AMI can be generated. After the signal we can also shutdown the instance.
Because the userdata has beend changed from the previous step, the instance is given a new logical
name in the template, creating a new instance and deleting the instance from the previous step.
2. A role is defined for a Lambda function to be able to create the AMI.
3. A lambda function is defined that based on the incoming event can create or delete the AMI.
4. A wait condition is defined to receive the signal from the EC2 instance, with a timeout of 10 minutes.
5. A custom resource for the AMI is defined that calls the Lambda function passing in the instance ID.

Remember to copy your web template to the S3 bucket, and update the parent template.

Resources:
- [Solution - Parent](solution/parent-04.yaml)
- [Solution - Instance](solution/web-02.yaml)
- [cfn-signal](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-signal.html)
- [AWS::IAM::Role](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-iam-role.html)
- [CAPABILITY_IAM](https://docs.aws.amazon.com/AWSCloudFormation/latest/APIReference/API_CreateStack.html)
- [AWS::Lambda::Function](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-lambda-function.html)
- [CreateImage](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/create_image.html)
- [AWS::CloudFormation::WaitCondition](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-cloudformation-waitcondition.html)

## 15 - What next?

***All of these options will incur more costs in your account.***

- NAT Gateways and routes for outgoing traffic from private subnets
- Application load balancer in public subnets
- AutoScaling Group for the web server using the AMI
- RDS database deployed in database subnets
