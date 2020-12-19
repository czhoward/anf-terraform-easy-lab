#Terraform Demo Lab
v1.0 Created by Kirk Ryan - Nov 2020
This configuration will deploy a configured Windows domain and a linux box.

#Instructions
This assumes you have already configured Terraform (terraform init) and are logged into Azure CLI (az login but really should look at making this user interaction free)

1. Change the default values in variables.tf to configure anything specific to your environment such as region.
2. Run the following command ```terraform deploy``` (perhaps run a terraform plan beforehand)

To clean-up the lab

1. Run ```Terraform destroy```
