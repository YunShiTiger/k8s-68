# shellcheck disable=SC2164
#cd log-gen
#docker build -t harbor.ls.com/lie/log-gen:v1 .
#docker push harbor.ls.com/lie/log-gen:v1
#cd ..
#kubectl -n mesoid create configmap filebeat --from-file=conf=./filebeat/filebeat.yml
kubectl apply -f efk.yaml
