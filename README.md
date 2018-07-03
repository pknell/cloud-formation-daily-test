# cloud-formation-daily-test
Example of daily automated CloudFormation stack creation and deletion.

The [Terraform template](https://github.com/pknell/cloud-formation-daily-test/blob/master/start-stop-environment.tf)
 sets up Lambda functions that are triggers each weekday by CloudWatch Rules.
These functions create a CloudFormation stack at a particular time and then delete it at a later time.

There is also an equivalent [CloudFormation template](https://github.com/pknell/cloud-formation-daily-test/blob/master/start-stop-environment-cf.yaml). Please note that the CloudFormation version of the template has the IAM policy and Lambda code embedded in the template, rather than referencing external files. External files are possible but they would need to be placed in S3.

## Maintenance Notes
The PNG file(s), such as diagram.png, were created using [www.draw.io](http://www.draw.io) and can be edited using that site.
