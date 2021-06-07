# shellcheck disable=SC2164
#cd log-gen
#docker build -t harbor.vackbot.com/liexing/log-gen:v1 .
#docker push harbor.vackbot.com/liexing/log-gen:v1
#cd ..
#kubectl -n mesoid create configmap filebeat --from-file=conf=./filebeat/filebeat.yml
kubectl apply -f efk.yaml
