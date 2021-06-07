brew install helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod +x get_helm.sh
./get_helm.sh


<!--
version.BuildInfo{Version:"v3.6.1", GitCommit:"61d8e8c4a6f95540c15c6a65f36a6dd0a45e7a2f", GitTreeState:"dirty", GoVersion:"go1.16.5"}
 -->
---

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add stable https://kubernetes.oss-cn-hangzhou.aliyuncs.com/charts
helm repo update
helm search repo mysql


### 自定义修改
helm show values bitnami/wordpress > wordpress.yaml
helm install -f wordpress.yaml bitnami/wordpress --generate-name
or
helm install bitnami/wordpress --generate-name
<!--
1. By chart reference: helm install mymaria stable/mariadb
2. By path to a packaged chart: helm install mynginx ./nginx-1.2.3.tgz
3. By path to an unpacked chart directory: helm install mynginx ./nginx
4. By absolute URL: helm install mynginx https://example.com/charts/nginx-1.2.3.tgz
5. By chart reference and repo url: helm install --repo https://example.com/charts/ mynginx nginx
-->
<!--
bitnami/wordpress  cannot create directory '/bitnami/mariadb/data': Permission denied
sudo chown -R 1001:1001 /data/volumes/
-->

