#!/bin/bash

k8s_server_url=`cat $HOME/.kube/config | grep server | tr -s " " | cut -d" " -f3 | tail -1`
k8s_cluster_name=`kubectl config get-contexts | grep '*' | tr -s " " | cut -d" " -f3`

mkdir $1 && cd $1

#Create a certificate for the $1 user

cat <<EOF | cfssl genkey - | cfssljson -bare $1
{
  "CN": "$1",
  "names": [
    {
        "O": "infra-team"
    }
  ],
  "key": {
    "algo": "rsa",
    "size": 4096
  }
}
EOF

#Create a ceritificate signing request

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1beta1
kind: CertificateSigningRequest
metadata:
  name: $1
spec:
  request: $(cat $1.csr | base64 | tr -d '\n')
  usages:
  - digital signature
  - key encipherment
  - client auth
EOF

#Approve the above certificate signing request
kubectl certificate approve $1

#Create a pem file for that user
kubectl get csr $1 -o jsonpath='{.status.certificate}' | grep -v +| base64 -d > $1.pem

#Create a cluster certificate for that user
kubectl config view -o json --raw | jq '.clusters[] | select (.name=='\"$k8s_cluster_name\"')| .cluster."certificate-authority-data"'|sed 's/"//g' | base64 -d > cluster.crt

#Setup the kubeconfig for the user
kubectl config set-cluster $k8s_cluster_name --server=$k8s_server_url --certificate-authority=cluster.crt --kubeconfig=$1-config --embed-certs

kubectl config set-credentials $1 --client-certificate=$1.pem --client-key=$1-key.pem --embed-certs --kubeconfig=$1-config

kubectl config set-context $1 --cluster=$k8s_cluster_name --user $1 --kubeconfig=$1-config

kubectl config use-context $1 --kubeconfig=$1-config
