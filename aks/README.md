
## Prerequisites
1. Create a resource group if you haven't got one ready for use. 
```bash
az deployment create \
  --name MY_RESOURCE_GROUP_NAME \
  --location eastus \
  --template-file ./resource-group.json
```

az deployment create \
  --name joshua-rg8 \
  --location eastus \
  --template-file ./resource-group.json

2. Don't create more than one AKS cluster in the same subnet.
3. AKS clusters may **not** use _169.254.0.0/16, 172.30.0.0/16, 172.31.0.0/16, or 192.0.2.0/24_ for the Kubernetes service address range.
4. To interact with Azure APIs, an AKS cluster requires an Azure Active Directory (AD) [Service Principal](https://docs.microsoft.com/en-us/azure/aks/kubernetes-service-principal). The service principal is needed to dynamically create and manage other Azure resources such as an Azure load balancer, container registry (ACR) etc

Unless specified, the SP is assigned the 'Contributor' role by default - this has full permissions to read and write to your Azure account which isn't ideal from a security standpoint.
Instead, create a new SP without any roles assigned to it. The template will then append the necessary permissions.
 
Create an SP like so:
```bash
az ad sp create-for-rbac --name "MY_RBAC_NAME" --skip-assignment
# Get the objectId using the appId from the response
az ad sp show --id <appId> --query objectId
```

NOTE: When you create a Service Principal, take note of the following in the response (redacted eg shown below):
```bash
{
  "appId": "2d3.....748",
  "displayName": "abcd..",
  "name": "http://abcd..",
  "password": "a07.....c0d",
  "tenant": "172.....f81"
}
```
- **Service principal Client ID** is your _**appId**_
- **Service principal Client Secret** is the _**password**_ value
- **Service principal Tenant ID** is the _**tenant**_ value


For this deployment we will provision (to your SP) and use the following permissions: 
```bash
# permissions on the subnet within your virtual network i.e Azure's `Network Contributor` role
- Microsoft.Network/virtualNetworks/subnets/join/action
- Microsoft.Network/virtualNetworks/subnets/read

# The VM where Helm is installed requires permissions to communicate with the cluster and provision Besu i.e Azure's `Azure Kubernetes Service Cluster Admin Role` role
- Microsoft.ContainerService/managedClusters/listClusterAdminCredential/action
```

## Description
This deployment template will create an AKS cluster for you in Azure, as well as a VM to run helm from to provision the cluster. Part of the process is that it will install Helm3 and the [Besu Helm charts](https://github.com/PegaSysEng/besu-kubernetes) in the home directory of the VM.

Once the deployment has completed, please ssh into the Helm VM (DNS address can be found in the outputs of the template), and use the credentials you supplied during provisioning.

To connect to the Kubernetes dashboard, please follow the steps under 'View Kubernetes dashboard' shown in the settings of your cluster in the [Azure Portal](https://portal.azure.com/) 

Pick any of the chart solutions and deploy to the cluster. For example say you pick 'ibft2':

```bash
cd $HOME
cd besu-kubernetes
cd helm\ibft2
helm install besu ./besu
```

To install an ingress to viw the Besu Grafana dashboards or connect to the RPC endpoint (grafana shown below, please select one or both when deploying and also apply the ingress rules):

```bash
cd $HOME
cd besu-kubernetes
cd ingress
helm install grafana-ingress stable/nginx-ingress --namespace monitoring --set controller.replicaCount=2 --set rbac.create=true
kubectl -f ingress-rules-grafana.yaml 
```


Once deployed, services are available as follows on the IP/ of the ingress controllers:

```bash

# Grafana address: 
http://<GRAFANA_INGRESS_IP>:80/d/XE4V0WGZz/besu-overview?orgId=1&refresh=10s

# HTTP RPC API:
curl -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' http://<BESU_INGRESS_IP>/jsonrpc/
# which should return (confirming that the node running the JSON-RPC service has peers):
{
  "jsonrpc" : "2.0",
  "id" : 1,
  "result" : "0x4"
}

# HTTP GRAPHQL API:
curl -X POST -H "Content-Type: application/json" --data '{ "query": "{syncing{startingBlock currentBlock highestBlock}}"}' http://<BESU_INGRESS_IP>/graphql/graphql/
# which should return 
{
  "data" : {
    "syncing" : null
  }
}


