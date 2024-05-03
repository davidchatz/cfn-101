# CloudFormation 101

A hands-on CloudFormation work that quickly dives into intermediate features of CloudFormation.

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

Create and deploy a simple VPC using CloudFormation by creating `template.yaml`, defining a VPC resource.

CloudFormation templates start with
- a format version `AWSTemplateFormatVersion: "2010-09-09"`
- optional description
- at least one resource
- comments start with a `#`

Each resource will have one or more properties, some properties are mandatory, others are optional. Read this documentation for the properties of a [VPC](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-vpc.html).

You can then deploy with:

```bash
STACK=cfn-demo
aws cloudformation create-stack \
    --stack-name $STACK \
    --template-body file://template.yaml
```

Resources:
- [CloudFormation Resources](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/gettingstarted.templatebasics.html#gettingstarted.templatebasics.multiple)
- [AWS::EC2::VPC](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-vpc.html)
- [Solution](solution/soln-01.yaml)

## 2 - Update VPC

Add a `Name` tag to the VPC in your `template.yaml`. But what name to give your VPC? Each CloudFormation stack must have a unique name, so using the name you gave your stack is often a good choice for at least part of your resource name. The stack name, and other details about your stack, can be used in your template using Psuedo Parameters:

```yaml
Value: !Ref "AWS::StackName"
```

Update the template by running

```bash
aws cloudformation update-stack \
    --stack-name $STACK \
    --template-body file://template.yaml
```

Resources:
- [CloudFormation Pseudo Parameters](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/pseudo-parameter-reference.html)
- [CloudFormation Updates](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-updating-stacks-direct.html)
- [AWS::EC2::VPC](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-vpc.html)
- [AWS::EC2::VPC tag](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ec2-vpc-tag.html)
- [Solution](solution/soln-02.yaml)

## 3 - Parameterise the VPC

Improve template reusability by [parameterising](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html) rather than hard-coding configuration values. We can still provide useful defaults with these parameters, and also perform input validation. For our template, we can parameterise the VPC CIDR block.

When defining your parameter, set the default to a different CIDR range than you were using, for example use `10.1.0.0/16` rather than `10.0.0.0/16`. CloudFormation can change some configurations in place, but this is not one of them. So what will happen when you update?

For input validation we can specify a list of allow values, or a regex that the input should match. Just in case you don't know this off the top of your head, here is a regex for a CIDR block.

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
    --template-body file://template.yaml \
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

However, not all dependencies are explicit. Add the following resources to your `template.yaml`:

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

Scroll down through this blog and you will see an example using `Fn::ForEach` in templates for subnets, including
- Adding the transform `Transform: AWS::LanguageExtensions`
- Using lists in parameters
- Loops (availability zone) within loops (tier)
- Mapping things like CIDR blocks

One of the limitations of `Fn::ForEach` is the order in which intrinsic functions are applied can complicate these definitions.
You will encounter this when trying to set the CIDR range for the templates. The blogs below suggest different approaches,
the solution provided is another approach again, with a combination of parameters and mappings.

It is left to the author to decide if the complexity of these loops is worth the lines of code saved.

Resources:
- [Foreach Blog](https://aws.amazon.com/blogs/devops/exploring-fnforeach-and-fnfindinmap-enhancements-in-aws-cloudformation/)
- [Another ForEach approach](https://dev.to/aws-builders/template-for-creating-a-3-layer-subnet-vpc-using-cloudformations-intrinsic-function-fnforeach-3fim)
- [Fn::ForEach](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-foreach.html)
- [Mapping](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/mappings-section-structure.html)
- [Fn::FindInMap](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-findinmap.html)
- [Template Macros and CAPABILITY_AUTO_EXPAND](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-macros.html)
- [Solution](solution/soln-07.yaml)

## 8 Outputs and Exports


## 9 - Master Template


## 10 - Security Group and Conditions


## 11 - Application Template


## 12 - Custom Resources

