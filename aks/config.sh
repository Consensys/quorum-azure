#!/bin/bash

AZURE_USER=$1
AZURE_SP_CLIENT_ID=$2
AZURE_SP_CLIENT_PASSWORD=$3
AZURE_SP_TENANT_ID=$4
AZURE_AKS_CLUSTER_NAME=$5
HOMEDIR="/home/$AZURE_USER"


function install_docker() {
  echo "Installing docker ..."
  curl -fsSL --max-time 10 --retry 3 --retry-delay 3 --retry-max-time 60 https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  apt-get update && apt-get install -y docker-ce
  usermod -aG docker $AZURE_USER
  systemctl enable docker
  systemctl restart docker
}

function install_az_cli() {
  echo "Installing az cli ..."
  curl -s https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key --keyring /etc/apt/trusted.gpg.d/microsoft.asc.gpg add -
  sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ bionic main" > /etc/apt/sources.list.d/azure.list'
  apt-get update && apt-get install -y azure-cli
  mkdir -p /root/.kube
  cd /root

  echo "az login ..."
  az login --service-principal -u "$AZURE_SP_CLIENT_ID" -p "$AZURE_SP_CLIENT_PASSWORD" -t "$AZURE_SP_TENANT_ID"

  #AZURE_SUBSCRIPTION_ID=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2018-10-01" | jq --raw-output '.compute.subscriptionId')
  AZURE_RG=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2018-10-01" | jq --raw-output '.compute.resourceGroupName')
  echo "az get-credentials ..."
  az aks get-credentials --resource-group "$AZURE_RG" --name "$AZURE_AKS_CLUSTER_NAME" --admin

  # install kubectl as part of this
  echo "az aks setup ..."
  az aks install-cli
}

function get_besu_charts(){
  # Besu charts
  git clone https://github.com/PegaSysEng/besu-kubernetes.git
  mv besu-kubernetes $HOMEDIR/
  chown -R $AZURE_USER:$AZURE_USER $HOMEDIR/besu-kubernetes
}

function install_helm(){
  echo "Installing helm ..."
  curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
  mkdir -p /root/.helm
  cd /root
  helm repo add stable https://kubernetes-charts.storage.googleapis.com/
}

function setup_user_permissions(){
  # Cant run scripts as a specific user! https://github.com/MicrosoftDocs/azure-docs/issues/13892
  echo "az setup for user $AZURE_USER ..."
  cp -r /root/.azure/ /root/.kube/ /root/.helm/ $HOMEDIR/
  chown -R $AZURE_USER:$AZURE_USER  $HOMEDIR/.azure/ $HOMEDIR/.kube/ $HOMEDIR/.helm/
}

# Install packages
apt-get update && apt-get install -y apt-transport-https ca-certificates curl software-properties-common git jq git
install_docker
install_az_cli
get_besu_charts
install_helm
setup_user_permissions

