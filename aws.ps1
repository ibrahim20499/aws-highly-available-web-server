
Import-Module AWSPowerShell 

#AWS Credentials 

$UserSecretKey = ""

$UserAccessKey = ""

$ProfileName = ""

$region = "us-east-1"

#Setting Credentials

$SetCredentials = Set-AWSCredential -AccessKey $UserAccessKey -SecretKey $UserSecretKey -StoreAs $ProfileName

#Setting Sessions

$session = Initialize-AWSDefaults -ProfileName $ProfileName  -Region $region

#----------------------------------------------------------------------------------------------------------------------------------------------

#---------------------- <Common Variables > -----------------------------------------

$yes = @("yes", "Yes" , "y" , "Y" )

$no = @("no", "No" , "n" , "N" )

#----------------------------------------------------------------------------------

#------------------------------------------------------------< Create VPC >--------------------------------------------------------------------

$askforvpc = Read-Host "Do you want to create a VPC [ yes | no ]"

if ($askforvpc -in $yes) {

    $VpcCidrBlock = Read-Host "Enter your vpc cider "
    $tags_vpc = @(
        @{
            Key   = "Name";
            Value = (Read-Host "Enter your tag value ")
        }
    )

    $myvpc = New-EC2Vpc -CidrBlock $VpcCidrBlock -InstanceTenancy "default" -Region $region  
    
    New-EC2Tag -Resource $myvpc.VpcId -Tag $tags_vpc

    Write-Output "VPC created with Id: $($myvpc.VpcId) and tag $($tags_vpc.Value)"
}
elseif ($askforvpc -in $no) {

    Write-Output "Thanks"

}
else {

    Write-Output " $askforvpc is not recognized please enter it correctly" 

}


#-----------------------------------------------< Create Internet Gateway >-------------------------------------------------------------------

$igw = New-EC2InternetGateway 
Add-EC2InternetGateway -VpcId $myvpc.VpcId -InternetGatewayId $igw.InternetGatewayId

$natgw = New-EC2NatGateway
#----------------------------------------------------------------------------------------------------------------------------------------------

#-----------------------------------------------< Create Subnets >-----------------------------------------------------------------------------

$myvpc = Get-EC2Vpc


$askforsubnet = Read-Host "Do you want to create a subnet [ yes | no ] "

$numberofsubnet = Read-Host "How many subnet do you want"

if ($askforsubnet -in $yes) {

    for ($i = 1; $i -le $numberofsubnet; $i++) {
       
        $SubnetCidrBlock = Read-Host "Enter your subnet $i cider "

        $SubnetAvailabilityZone = Read-Host "Enter your subnet $i AvailabilityZone "
        #$SubnetTagValue = Read-Host "Enter your subnet $i tag "
        
        $mySubnets = New-EC2Subnet -CidrBlock $SubnetCidrBlock -VpcId  $myvpc.VpcId  -AvailabilityZone $SubnetAvailabilityZone #"vpc-03c1cd9f299c225c8" 

        $tags = @(
            @{
                Key   = "Name";
                Value = (Read-Host "Enter your subnet $i tag ")
            }
        )

        New-EC2Tag -Resource $mySubnets.SubnetId -Tag $tags

        Write-Output "Subnet $i created with Id: $($mySubnets.SubnetId) and tag $($tags.Value)"

    }
    
}
elseif ($askforsubnet -in $no) {
    Write-Output "Thanks there is no subnet created"
}
else {
    Write-Output " $askforsubnet is not recognized please enter it correctly"
}

#----------------------------------------------------------------------------------------------------------------------------------------------

#-------------------------------------------< Create tags for subnet already created >----------------------------------------------------------

#---------------------------------------------------------------------------------------------------------------------------------------------------

function Subnet_Search {
    $allsubnet , $subnet_num , $output = $null
    $allsubnet = Get-EC2Subnet 
    $i =1
    foreach($subnet_num in $allsubnet){
        $output = Write-Output " $i. $($subnet_num.SubnetId) <-----> $($subnet_num.Tags.value)"
        $output | Format-Table
        $i++
    } 
}

#-----------------------------------------------< Create Route Tables and associate to Subnets >----------------------------------------------------------------

$subnets = Get-EC2Subnet
$igw = Get-EC2InternetGateway
$ngw = Get-EC2NatGateway
#$routeTable = Get-EC2RouteTable | Format-Table

foreach ($subnet in $subnets) {
    $subnetId = $subnet.SubnetId 

    $publicRouteTable = New-EC2RouteTable -VpcId $myvpc.VpcId  #"vpc-03c1cd9f299c225c8" 

    if ($subnet.Tag.value -like "public*") {
        
        New-EC2Route -RouteTableId $publicRouteTable.RouteTableId `
                     -DestinationCidrBlock 0.0.0.0/0 `
                     -GatewayId $igw.InternetGatewayId 

        Write-Output "you are in public"

        $tags = @(
            @{
                Key   = "Name";
                Value = (Read-Host "Enter your Route table tag value ")
            }
        )
    
        New-EC2Tag -Resource $($publicRouteTable.RouteTableId)  -Tag $tags
    
        Register-EC2RouteTable -RouteTableId $publicRouteTable.RouteTableId -SubnetId $subnet.SubnetId
    
        #Write-Output "Route table $($publicRouteTable.RouteTableId)  created with tag: $($tags.Value) "
    
        Write-Output "Route Table With id: $($publicRouteTable.RouteTableId) created and tag: $($tags.Value) is associate to subnet id: $($subnetId) "
    
    }
    elseif ( $subnet.Tag.value  -like "private*") {
       
        Subnet_Search
        [String]$subnetId = Read-Host "choose your subnet that you want to create your Nat Gateway "
        
        $elip = New-EC2Address -Domain Vpc

        $natgw = New-EC2NatGateway -SubnetId $subnetId -AllocationId $elip.AllocationId -ConnectivityType public 

        $publicRouteTable = New-EC2RouteTable -VpcId $myvpc.VpcId  #"vpc-03c1cd9f299c225c8" 

        New-EC2Route -RouteTableId $publicRouteTable.RouteTableId `
                     -DestinationCidrBlock 0.0.0.0/0 `
                     -NatGatewayId $natgw.NatGateway.NatGatewayId

        Write-Output "you are in private"

        $tags = @(
                @{
                    Key   = "Name";
                    Value = (Read-Host "Enter your Route table tag value ")
                }
            )
        
            New-EC2Tag -Resource $($publicRouteTable.RouteTableId)  -Tag $tags
        
            Register-EC2RouteTable -RouteTableId $publicRouteTable.RouteTableId -SubnetId "subnet-010bcbfca4e12b1db" #$subnet.SubnetId
                
            Write-Output "Route Table With id: $($publicRouteTable.RouteTableId) created and tag: $($tags.Value) is associate to subnet id: $($subnetId) "
        
    }

}

#----------------------------------------------------------------------------------------------------------------------------------------------------

#-----------------------------------------------< Create EC2 Instances with Security Group >----------------------------------------------------------------

$keyPair = (New-EC2KeyPair -KeyName "my-key-pair").KeyMaterial | Out-File -Encoding ascii my-key-pair.pem


Get-EC2KeyPair

$userData = @"
#!/bin/bash
sudo yum update -y
sudo yum install -y httpd
sudo systemctl start httpd
sudo systemctl enable --now httpd
sudo echo "web server 1" > /var/www/html/index.html
"@
$encodedUserData = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userData))

$vpc = Get-EC2vpc
$subnets = Get-EC2Subnet

$askforinstance = Read-Host "Do you want to create a instance [ yes | no ] "

$numberofinstance = Read-Host "How many instance do you want"

if ($askforinstance -in $yes) {

    for ($i = 1; $i -le $numberofinstance; $i++) {
       
        
        #-------------------------------< Create Security Group > --------------------------------------------------------------------------------
        $SecurityGroupParams = @{
            GroupName   = Read-Host "Enter your Security group name"
            Description = Read-Host "Enter your Security group Description"
            VpcId       = $vpc.VpcId
        }
        
        $ec2_security = New-EC2SecurityGroup @SecurityGroupParams
            
        #Get-EC2SecurityGroup

        $numberofSG = Read-Host "How many permissions do you want"

        for ($n = 1; $n -le $numberofSG; $n++) {
            $IpPermission = @{
                IpProtocol = Read-Host "Enter your $n protocol "
                FromPort   = Read-Host "Enter your $n FromPort"
                ToPort     = Read-Host "Enter your $n ToPort"
                IpRanges   = Read-Host "Enter your $n IpRanges"
            }

            $ec2_security | Grant-EC2SecurityGroupIngress -IpPermission $IpPermission 

        }

        $tags = @(
            @{
                Key   = "Name";
                Value = (Read-Host "Enter your Security Group $i tag ")
            })

        New-EC2Tag -Resource $ec2_security -Tag $tags    
        Write-Output "Security group created with Id: $($ec2_security) and tag $($tags.Value)"

        #--------------------------------------------------------------------------------------------------------------------------------------       
        #-----------------------------------------------< Create EC2 Instances >--------------------------------------------------------------
       
        $(Subnet_Search) 
        $SubnetCidrBlock = Read-Host "choose your subnet that you want to create your instance "

        $params = @{
            ImageId           = "ami-079db87dc4c10ac91"
            AssociatePublicIp = $false
            InstanceType      = 't2.micro'
            SubnetId          = $SubnetCidrBlock
            KeyName           = 'new'
            SecurityGroupId   = "$ec2_security"
            UserData          = $encodedUserData
            
        }

        $myInstance = New-EC2Instance @params 

        $tags = @(
            @{
                Key   = "Name";
                Value = (Read-Host "Enter your instance $i tag ")
            }
        )

        New-EC2Tag -Resource $myInstance.Instances.InstanceId -Tag $tags
        Write-Output "instance $i created with Id: $($myInstance.Instances.InstanceId) and tag $($tags.Value)"

    }
    
}
elseif ($askforinstance -in $no) {

    Write-Output "Thanks there is no ec2 created"
}
else {
    Write-Output " $askforinstance is not recognized please enter it correctly "
    
}


#-------------------------------< Create Elastic Load Balancer> --------------------------------------------------------------------------------

function Create_ELB {
    $vpc = Get-EC2vpc
    $subnets = Get-EC2Subnet

    $askforELB = Read-Host "Do you want to create an ELB [ yes | no ] "

    if ($askforELB -in $yes) {
        $SecurityGroupParams = @{
            GroupName   = Read-Host "Enter your Security group name"
            Description = Read-Host "Enter your Security group Description"
            VpcId       = $vpc.VpcId
        }
    
        $elb_security = New-EC2SecurityGroup @SecurityGroupParams
        
        #Get-EC2SecurityGroup
    
        $numberofSG = Read-Host "How many permissions do you want"
    
        for ($i = 1; $i -le $numberofSG; $i++) {
            $IpPermission = @{
                IpProtocol = Read-Host "Enter your $i protocol "
                FromPort   = Read-Host "Enter your $i FromPort"
                ToPort     = Read-Host "Enter your $i ToPort"
                IpRanges   = Read-Host "Enter your $i IpRanges"
            }
    
            $elb_security | Grant-EC2SecurityGroupIngress -IpPermission $IpPermission 
    
        }
        Subnet_Search
        $elb_subnets = (Read-Host "Enter the subnet IDs for your ELB") -split ','
        $elb = New-ELB2LoadBalancer -Name 'New-ELB' `
            -Type application `
            -Scheme internet-facing `
            -IpAddressType ipv4 `
            -SecurityGroup $elb_security `
            -Subnet $elb_subnets 
                                
    }
    
}

function Create_Target_Group {
   $myvpc = Get-Ec2Vpc
    $targetGroup = New-ELB2TargetGroup -Name "MyTarget" `
                                       -Protocol HTTP `
                                       -Port 80 `
                                       -VpcId $myvpc.VpcId `
                                       -TargetType instance `
                                       -HealthCheckProtocol HTTP `
                                       -HealthCheckPath "/" `
                                       -HealthCheckIntervalSeconds 30 -HealthyThresholdCount 2


    $target = Get-ELB2TargetGroup
    $ELB = Get-ELB2LoadBalancer
    $instances = Get-EC2Instance
    $num_ec2_targets = Read-Host "How many ec2 targets you want to register to Target Group"

        for ($i = 1; $i -le $num_ec2_targets; $i++) {
            $ec2_targets_id = Read-Host "enter  your ec2 [$i] targets you want to register to Target Group"

          $targets =   @{
                Port = 80
                Id   = $ec2_targets_id
            }

            Register-ELB2Target -TargetGroupArn $target.TargetGroupArn -Target @($targets) 

        }
      
}
            


# Create a listener to forward traffic from ALB to the target group
$listener = New-ELB2Listener -LoadBalancerArn $ELB.LoadBalancerArn `
                             -Protocol HTTP `
                             -Port 80 `
                             -DefaultActions @{Type = "forward"; TargetGroupArn = $target.TargetGroupArn }


#------------------------------------------------------------------------------------------------------------------------------------------------

New-EC2Image -InstanceId i-098f2516e318916a8 -Name "Web Server" -Description "web-server-AMI" -NoReboot $true

#-----------------------------------------------------<Launch Configuraton>-----------------------------------------------------------------------------

$launchConfigurationName = "MyLaunch"
$imageId = "ami-0a6bf3dca761dd5ec"
$instanceType = "t2.micro"
$keyName = "new"
$securityGroups = @("sg-0f3eec3e378a464e3")
$userData = @"
#!/bin/bash
sudo yum update -y
sudo yum install -y httpd
sudo systemctl disable --now firewalld
sudo systemctl start httpd
sudo systemctl enable --now httpd
sudo echo "web server 3" > /var/www/html/index.html

"@

$elb = Get-ELB2LoadBalancer

# Create the launch configuration
New-ASLaunchConfiguration -LaunchConfigurationName $launchConfigurationName `
                          -ImageId $imageId `
                          -InstanceType $instanceType `
                          -KeyName $keyName `
                          -SecurityGroups $securityGroups `
                          -UserData $encodedUserData

#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

$TargetGroup = Get-ELB2TargetGroup

New-ASAutoScalingGroup -AutoScalingGroupName new-asg  -LaunchTemplate_LaunchTemplateName  "MyTemplate" -MinSize 2 -DesiredCapacity 2 -MaxSize 4 -TargetGroupARNs $TargetGroup.TargetGroupArn  -AvailabilityZone @("us-east-1a", "us-east-1b") -
New-ASAutoScalingGroup -AutoScalingGroupName new-asg `
                       -LaunchConfigurationName MyLaunch `
                       -MinSize 2 `
                       -DesiredCapacity 2 `
                       -MaxSize 4 `
                       -TargetGroupARNs $TargetGroup.TargetGroupArn `
                       -VPCZoneIdentifier "subnet-02790dd2ad1672ca7, subnet-0689350ba79ae9cbc"

Write-ASScalingPolicy -AutoScalingGroupName new-asg `
                      -PolicyName Write-ASScalingPolicy `
                      -PolicyType TargetTrackingScaling `
                      -TargetTrackingConfiguration_TargetValue 50 `
                      -PredefinedMetricSpecification_PredefinedMetricType "ASGAverageCPUUtilization" `
                      -Cooldown 300 

Get-ASAutoScalingGroup
Remove-ASAutoScalingGroup -AutoScalingGroupName new-asg -Force

Update-ASAutoScalingGroup -AutoScalingGroupName new-asg -DesiredCapacity 0 -MaxSize 0 -MinSize 0

Get-ASPolicy -AutoScalingGroupName new-asg -PolicyName  "Write-ASScalingPolicy"

Remove-ASPolicy -AutoScalingGroupName new-asg -PolicyName  "Write-ASScalingPolicy"
#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

function Create_Launch_Template {

    $data = @"
#!/bin/bash
sudo yum update -y
sudo yum install -y httpd
sudo systemctl disable --now firewalld
sudo systemctl start httpd
sudo systemctl enable --now httpd 
sudo echo "web server 3" > /var/www/html/index.html
"@ 
  
    $encodedUserData = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($data))

    $LaunchTemplate = New-EC2LaunchTemplate -LaunchTemplateName MyTemplate `
        -LaunchTemplateData @{
        ImageId        = "ami-0a6bf3dca761dd5ec"  # Replace with your AMI
        InstanceType   = "t2.micro"
        SecurityGroups = @("sg-0f3eec3e378a464e3")  # Replace with your security group
        UserData       = $encodedUserData
    }

}


#-------------------------------------------------------------------------------------------------------------------------------------

Get-EC2Template
Get-ASLaunchConfiguration
Remove-ASLaunchConfiguration -LaunchConfigurationName "MyLaunchConfig"
Remove-EC2LaunchTemplate -LaunchTemplateId "lt-0850bdde6ac498ae7" -Force

#-----------------------------------------------------------< Remove Resources >---------------------------------------------------------------

#---------------------------------< Remove  ELB & Listener && Target group > ---------------------------------------------------
$target = Get-ELB2TargetGroup
$ELB = Get-ELB2LoadBalancer
$listenerArn = Get-ELB2Listener -LoadBalancerArn $ELB.LoadBalancerArn
Remove-ELB2Listener -ListenerArn $listenerArn.ListenerArn -Force
Remove-ELB2LoadBalancer -LoadBalancerArn $ELB.LoadBalancerArn -Force
Remove-ELB2TargetGroup -TargetGroupArn $target.TargetGroupArn -Force

#-------------------------------------------------------------------------------------------------------------------------------------------

#---------------------------------< Remove Security Group > --------------------------------------------------------------------------
$securits = Get-EC2SecurityGroup

foreach ($security in $securits) {
    Remove-EC2SecurityGroup -GroupId $security.GroupId -Force
}
#--------------------------------------------------------------------------------------------------------------------------------------
#---------------------------------< Remove Route Tables > --------------------------------------------------------------------------
$routes = Get-EC2RouteTable 

foreach ($routeTable in $routes) {
    #Remove-EC2RouteTableAssociation -AssociationId $routeTable.Associations -Force
    Remove-EC2RouteTable -RouteTableId $routeTable.RouteTableId -Force
}
#-----------------------------------------------------------------------------------------------------------------------------
#---------------------------------< Remove Subnets  > --------------------------------------------------------------------------
$subnets = Get-EC2Subnet 

foreach ($subnet in $subnets) {

    Remove-EC2Subnet -SubnetId $subnet.SubnetId -Force
}

#------------------------------------------------------------------------------------------------------------------------------
Get-EC2Image 
#---------------------------------< Remove EC2 && VPC > -----------------------------------------------------------------------------
$inst = Get-EC2Instance
$internetGateway = Get-EC2InternetGateway
$VPC = Get-EC2Vpc
Remove-EC2Instance -InstanceId i-02dafc6270f437488   -Force
Disable-EC2Image -ImageId "ami-0a6bf3dca761dd5ec" -Force
Remove-EC2InternetGateway -InternetGatewayId $internetGateway.InternetGatewayId   -Force
Remove-EC2Vpc -VpcId $VPC.VpcId -Force 
Dismount-EC2InternetGateway -VpcId $VPC.VpcId -InternetGatewayId $internetGateway.InternetGatewayId -Force


$nat = Get-EC2NatGateway

foreach ($nategatway in $nat) {

    Remove-EC2NatGateway -NatGatewayId "nat-0f849666ab82be867" -Force
}

Get-EC2NetworkAcl -Filter @{ Name = "vpc-id"; Values = "$($VPC.VpcId)" } | Remove-EC2NetworkAcl

#--------------------------------------------------------------------------------------------------------------------------------------

Get-EC2Address
Remove-EC2Address -AllocationId eipalloc-02d83ff2051ff1cd0 -Force
Remove-EC2Address -PublicIp 54.174.166.121  -Force
Disable-Ec -PublicIp 54.174.166.121
Get-EC2NatGateway
Get-Ec2InternetGateway
Get-Ec2Vpc






New-DDBTableSchema | Add-DDBIndexSchema -IndexName "LastPostIndex" -RangeKeyName "LastPostDateTime" -RangeKeyDataType "S" -ProjectionType "keys_only"
New-DDBTable -TableName "CustomerInfo" -ReadCapacity 5 -WriteCapacity 5 

$schema = New-DDBTableSchema
$schema | Add-DDBKeySchema -KeyName "ForumName" -KeyDataType "S"
$schema | New-DDBTable -TableName "CustomerInfo" -ReadCapacity 5 -WriteCapacity 5 

Remove-DDBTable -TableName "CustomerInfo"
Get-DDBTable




Get-SSMLatestEC2Image

$in = Get-EC2Instance

foreach ($instance in $in) {
    Remove-EC2Instance -InstanceId $instance.Instances.InstanceId -force
}

(Get-EC2Instance -Filter @{Name = "vpc-id"; Values = $myvpc.VpcId }).Instances
Get-EC2SecurityGroupRule