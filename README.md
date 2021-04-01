
## Background
1. Don't create more than one AKS cluster in the same subnet.
2. AKS clusters may **not** use _169.254.0.0/16, 172.30.0.0/16, 172.31.0.0/16, or 192.0.2.0/24_ for the Kubernetes service address range.
3. To interact with Azure APIs, an AKS cluster requires an Azure Active Directory (AD) [Service Principal](https://docs.microsoft.com/en-us/azure/aks/kubernetes-service-principal) or a [Mananged Identity](https://docs.microsoft.com/en-us/azure/aks/use-managed-identity). Either is needed to dynamically create and manage other Azure resources such as an Azure load balancer, container registry (ACR) etc
4. CNI Networking
By default, AKS clusters use **kubenet**, and a virtual network and subnet are created for you. With kubenet, nodes get an IP address from a virtual network subnet. Network address translation (NAT) is then configured on the nodes, and pods receive an IP address "hidden" behind the node IP. This approach reduces the number of IP addresses that you need to reserve in your network space for pods to use, however places constraints on what can connect to the nodes from outside the cluster (eg on prem nodes)

With Azure Container Networking Interface (CNI), every pod gets an IP address from the subnet and can be accessed directly. These IP addresses must be unique across your network space, and must be planned in advance. Each node has a configuration parameter for the maximum number of pods that it supports. The equivalent number of IP addresses per node are then reserved up front for that node. This approach requires more planning, and can leads to IP address exhaustion as your application demands grow, however makes it easier for external nodes to connect to your cluster.

![Image aks_cni](./static/aks_cni.png)

 If you have existing VNets, you can easily connect to the VNet with the k8s cluster by using [VNet Peering](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview)



## Prerequisites:
For this deployment we will provision AKS with CNI and a managed identity to authenticate and run operations of the cluster with other services. We also enable [AAD pod identities](https://docs.microsoft.com/en-us/azure/aks/use-azure-ad-pod-identity) which use the managed identity. This is in preview so you need to enable this feature by registering the EnablePodIdentityPreview feature:
```bash
az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService
```
This takes a little while and you can check on progress by:
```bash
az feature list --namespace Microsoft.ContainerService -o table
```

Then install the aks-preview Azure CLI
```bash
az extension add --name aks-preview 
az extension update --name aks-preview 
```

Create a resource group if you haven't got one ready for use. 
```bash 
az group create --name ExampleGroup --location "East US"
```


## Description
This deployment template will create an AKS cluster for you in Azure, as well as a VM to run helm from to provision the cluster. Part of the process is that it will install Helm3 and the [Besu Helm charts](https://github.com/PegaSysEng/besu-kubernetes) in the home directory of the VM.

## Deployment

1. Deploy the template
* Navigate to the [Azure portal](https://portal.azure.com), click `+ Create a resource` in the upper left corner.
* Search for `Template deployment (deploy using custom templates)` and click Create.
* Click on `Build your own template in the editor`
* Remove the contents (json) in the editor and paste in the contents of `azuredeploy.json`
* Click Save
* The template will be parsed and a UI will be shown to allow you to input parameters to provision

Alternatively use the CLI
```bash
az deployment create \
  --name blockchain-aks \
  --location eastus \
  --template-file ./azuredeploy.json \
  --parameters env=dev location=eastus 
```

2. Provision Drivers

Once the deployment has completed, please run the [bootstrap](../scripts/bootstrap.sh) to provision the AAD pod identity and the CSI drivers

Use `besu` or `quorum` for AKS_NAMESPACE depending on which blockchain client you are using

```bash
../scripts/bootstrap.sh "AKS_RESOURCE_GROUP" "AKS_CLUSTER_NAME" "AKS_MANAGED_IDENTITY" "AKS_NAMESPACE"
```

3. Deploy the charts 

*For Besu:*
```bash

cd helm/dev/
helm install monitoring besu-monitoring --namespace monitoring --create-namespace 
helm install genesis ./charts/besu-genesis --namespace besu --values ./values/genesis.yml 

helm install bootnode-1 ./charts/besu-node --namespace besu --values ./values/bootnode.yml
helm install bootnode-2 ./charts/besu-node --namespace besu --values ./values/bootnode.yml

helm install validator-1 ./charts/besu-node --namespace besu --values ./values/validator.yml
helm install validator-2 ./charts/besu-node --namespace besu --values ./values/validator.yml
helm install validator-3 ./charts/besu-node --namespace besu --values ./values/validator.yml
helm install validator-4 ./charts/besu-node --namespace besu --values ./values/validator.yml

# spin up a besu and orion node pair
helm install tx-1 ./charts/besu-node --namespace besu --values ./values/txnode.yml

```

Optionally deploy the ingress controller like so in the `monitoring` namespace:
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install grafana-ingress ingress-nginx/ingress-nginx \
    --namespace monitoring \
    --set controller.name=grafana-ingress \
    --set controller.watchNamespace=monitoring \
    --set controller.ingressClass=grafana \
    --set controller.replicaCount=2 \
    --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set rbac.create=true

kubectl apply -f ./ingress/ingress-rules-grafana.yml
```

*For Quorum:*
```
TO BE ADDED..
```


4. Once deployed, services are available as follows on the IP/ of the ingress controllers:

*For Besu:*
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



