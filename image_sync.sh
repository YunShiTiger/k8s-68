#!/bin/bash
cat >sync_image.sh <<\EOF
#set -x xtrace
#export PS4='[Line:${LINENO}] '
sync() {
  address=$1
  # shellcheck disable=SC2206
  arr=(${address//\// })
  Repo=${arr[${#arr[@]} - 1]}
  echo $Repo1
  echo gcloud container images list-tags $address

  address=k8s.gcr.io/kube-state-metrics/kube-state-metrics
  for tag in $(gcloud container images list-tags $address); do
    if [[ "$tag" == "TAGS:" ]] || [[ "$tag" == "DIGEST:" ]]; then
      continue
    else

      if [[ "$tag" =~ [0-9a-zA-Z]{12}$ ]]; then
        continue
      else
        echo -e "\033[34mpulling  $address:$tag\033[0m"
        docker pull $address:$tag
        docker tag $address:$tag acejilam/$Repo:$tag
        docker push acejilam/$Repo:$tag
        echo -e "\033[32msync  acejilam/$Repo:$tag\033[0m"
        docker rmi acejilam/$Repo:$tag
        docker rmi $address:$tag
      fi
    fi

  done
}
sync 'k8s.gcr.io/kube-state-metrics/kube-state-metrics'
sync 'k8s.gcr.io/ingress-nginx/controller'
sync 'k8s.gcr.io/networking/ip-masq-agent-amd64'
sync 'k8s.gcr.io/sig-storage/csi-snapshotter'
sync 'k8s.gcr.io/sig-storage/csi-attacher'
sync 'k8s.gcr.io/sig-storage/hostpathplugin'
sync 'k8s.gcr.io/sig-storage/livenessprobe'
sync 'k8s.gcr.io/sig-storage/csi-provisioner'
sync 'k8s.gcr.io/node-problem-detector/node-problem-detector'
sync 'k8s.gcr.io/metrics-server-amd64'
sync 'k8s.gcr.io/fluentd-gcp'
sync 'k8s.gcr.io/sig-storage/csi-node-driver-registrar'
sync 'k8s.gcr.io/sig-storage/csi-resizer'
EOF
chmod +x sync_image.sh
bash sync_image.sh
