# cloud-formation-daily-test
Example of daily automated CloudFormation stack creation and deletion.

The Terraform template sets up Lambda functions that are triggers each weekday by CloudWatch Rules.
These functions create a CloudFormation stack at a particular time and then delete it at a later time.

## Maintenance Notes
The PNG file(s), such as diagram.png, were created using www.draw.io and can be edited using that site.