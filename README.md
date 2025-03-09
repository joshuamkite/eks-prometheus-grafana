# EKS with Prometheus; Grafana; Load Balancer Controller

> [!IMPORTANT]  
> This repository has now been archived - it is not current or maintained. Please refer to other repos for more current code

Deploy an EKS cluster with Terraform/Tofu and deploy Prometheus and Grafana in 2 ways: either quick and dirty using kubectl and port forwarding, or more elegantly with Helm and using Load balancer controller with IAM Roles for Service Accounts for endpoint access.

- [EKS with Prometheus; Grafana; Load Balancer Controller](#eks-with-prometheus-grafana-load-balancer-controller)
  - [Version 1 - quick and dirty](#version-1---quick-and-dirty)
  - [Version 2 - Helm with load balancer controller](#version-2---helm-with-load-balancer-controller)
    - [Cleanup](#cleanup)
  - [Notes](#notes)

## Version 1 - quick and dirty

Based on https://www.youtube.com/watch?app=desktop&v=S41v1lVThds

Deploy and configure access to cluster.

Check cluster
```bash
kubectl get pods -n kube-system 
```
Add metrics server
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```
Check metrics server
```bash
kubectl get pods -n kube-system 
kubectl get deployments -n kube-system 
```
Add prometheus-community helm charts
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
```
Install charts 
```bash
helm install prometheus \
 prometheus-community/kube-prometheus-stack \ --namespace monitoring \
 --create-namespace \
 --set alertmanager.persistentVolume.storageClass="gp2",server.persistVolume.storageClass="gp2"
```
check services deployed
```bash
kubectl get all -n monitoring 
```
Set port forward for Prometheus
```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 4001:9090
```
access on `127.0.0.1:4001`

Get password for grafana (username is `admin`)
```bash
kubectl get secret --namespace monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```
port forward grafana 
```
kubectl port-forward service/prometheus-grafana 3000:80 --namespace monitoring
```
access on `127.0.0.1:80`

## Version 2 - Helm with load balancer controller

Assumes cluster is deployed from `terraform` directory and kube api access

Based on 
https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.7/deploy/installation/

IAM set up with terraform with cluster

create load balancer controller service account - I am using env vars to interpolate account ID and my home CIDR:

```bash
cd  terraform
export AWS_ACCOUNT_ID=${your_aws_account_id}
export TF_VAR_cidr_passlist=${your_cidr}
tofu init
tofu apply
```

Set up ~/.kube/config:

```bash
aws eks list-clusters 
aws eks update-kubeconfig --name personal-eks-workshop
```

Create service account for Load Balancer controller

```bash
cd helm/
envsubst < aws-load-balancer-controller-sa.yaml | kubectl apply -f -
```
(equivalent to `kubectl apply -f aws-load-balancer-controller-sa.yaml` with env var)

Install load balancer controller:

```bash
helm repo add eks https://aws.github.io/eks-charts

helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=personal-eks-workshop --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller

```
Add metrics server
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```
Add prometheus-community helm charts
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
```
Install charts referencing custom values file
```bash
helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace --set alertmanager.persistentVolume.storageClass="gp2",server.persistVolume.storageClass="gp2" --values grafana-prometheus-custom-values.yaml
```

Find load balancer URLs for prometheus and Grafana (value in each case for `LoadBalancer Ingress` field):
```bash


kubectl get svc -n monitoring -l "app.kubernetes.io/name=grafana" -o yaml
kubectl get svc prometheus-kube-prometheus-prometheus -n monitoring -o yaml

```
or just
```bash
kubectl get svc -n monitoring 
```

Access works

<LoadBalancer Ingress>:<PORT>   

e.g.

Prometheus

http://ae99a3324ecde4748897e05f85bd0093-0f75be85f47bddef.elb.eu-west-1.amazonaws.com:9090

Grafana

http://ac4b5b9e183aa4228a88e27a5f85fb5e-c205708f2ad48239.elb.eu-west-1.amazonaws.com

get secret to log in to Grafana (default username is 'admin')
```bash
kubectl get secret --namespace monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```
prometheus is available on port 9090

### Cleanup

Uninstall the Helm release. This is required to remove indirectly created resources such as load balancers, otherwise `tofu destroy` will fail on VPC deletion

```
helm uninstall prometheus --namespace monitoring
```

Tear down environment:

```
tofu destroy
```

## Notes

- We are using a simple IAM user rather than 'proper' roles to admin cluster 
- Services are world open. In production we would make these private behind a VPN or similar. Here we use NACLs to restrict access to our IP for demo.
- load balancers won't be deleted as part of cluster `tofu destroy` and will block teardown of resources unless deployments removed first or deleted manually with, e.g. `helm uninstall prometheus -n monitoring`
- Here we are using unencrypted http to access endpoints and Load balancer URLS. In production I would alias these with a a proper domain name and set up certificate manager or similar to support TLS encryption.
- I am not committing my `backend.tf` file to source control because I don't want to disclose my AWS account number.