#!/bin/bash
#docker login -uacejilam -p$1
#cat >sync_image.sh <<\EOF
#set -x xtrace
#export PS4='[Line:${LINENO}] '

get_all_tag() {
  url=$1
  curl -o ~/res.txt -s $url
  tags=$(echo "$(cat ~/res.txt | jq -r '.results[].name')")
  next=$(echo "$(cat ~/res.txt | jq -r '.next')")
  while [[ $next != null ]]; do
    curl -o ~/res.txt -s $next
    tmp_tags=$(echo "$(cat ~/res.txt | jq -r '.results[].name')")
    next=$(echo "$(cat ~/res.txt | jq -r '.next')")
    tags="$tags $tmp_tags"
  done
  echo $tags
}

sync() {
  address=$1
  args=(${address//\// })
  Repo=${args[${#args[@]} - 1]}
  page=1
  all_tag=$(get_all_tag https://hub.docker.com/v2/repositories/acejilam/$Repo/tags/?page_size=1000)
  OLD_IFS="$IFS"
  IFS=" "
  arr=($all_tag)
  IFS="$OLD_IFS"
  len=0
  for s in ${arr[@]}; do
    ((len++))
  done

  total=0
  echo "gcloud container images list-tags $address"
  for tag in $(gcloud container images list-tags $address | xargs -n 1 |grep -v -E 'DIGEST|TAGS|TIMESTAMP'); do
    if [[ "$tag" == "TAGS:" ]] || [[ "$tag" == "DIGEST:" ]] || [[ "$tag" =~ [0-9a-zA-Z]{12}$ ]] || [[ "$tag" =~ [0-9T:\-]{19}$ ]] || [[ "$tag" =~ , ]]; then
      continue
    else
      ((total++))
    fi
  done
  echo "$address [$total] 已转存 $len"
  echo $all_tag
  if [[ $total == $len ]]; then
    return
  fi

  for tag in $(gcloud container images list-tags $address | xargs -n 1 |grep -v -E 'DIGEST|TAGS|TIMESTAMP'); do
    if [[ "$tag" == "TAGS:" ]] || [[ "$tag" == "DIGEST:" ]] || [[ "$tag" =~ [0-9a-zA-Z]{12}$ ]] || [[ "$tag" =~ T ]] || [[ "$tag" =~ , ]]; then
      continue
    else
      # 判断镜像是否存在
      flag=false
      for item in $all_tag; do
        if [ "$item" == "$tag" ]; then
          echo -e "\033[32m存在  acejilam/$Repo:$tag\033[0m"
          flag=true
          break
        fi
      done
      if [ "$tag" == "latest" ]; then
        flag=false
      fi
      if $flag; then
        continue
      else
        address=$(echo $address)
        echo -e "\033[34mpulling  $address:$tag\033[0m"
        docker pull $address:$tag
        docker tag $address:$tag acejilam/$Repo:$tag
        docker push acejilam/$Repo:$tag
        ((len++))
        ((lest=total-len))
        echo -e "\033[32m $lest sync  acejilam/$Repo:$tag\033[0m"
        docker rmi acejilam/$Repo:$tag
        docker rmi $address:$tag
      fi
    fi
  done
}
#sync 'k8s.gcr.io/kube-state-metrics/kube-state-metrics'
#sync 'k8s.gcr.io/ingress-nginx/controller'
#sync 'k8s.gcr.io/networking/ip-masq-agent-amd64'
#sync 'k8s.gcr.io/sig-storage/csi-snapshotter'
#sync 'k8s.gcr.io/sig-storage/csi-attacher'
#sync 'k8s.gcr.io/sig-storage/hostpathplugin'
#sync 'k8s.gcr.io/sig-storage/livenessprobe'
#sync 'k8s.gcr.io/sig-storage/csi-provisioner'
#sync 'k8s.gcr.io/node-problem-detector/node-problem-detector'
#sync 'k8s.gcr.io/metrics-server-amd64'
#sync 'k8s.gcr.io/fluentd-gcp'
#sync 'k8s.gcr.io/sig-storage/csi-node-driver-registrar'
#sync 'k8s.gcr.io/sig-storage/csi-resizer'
#sync 'k8s.gcr.io/coredns'
#sync 'gcr.io/google-samples/gb-frontend'
#sync 'k8s.gcr.io/pause'
#sync 'k8s.gcr.io/kube-controller-manager'
#sync 'k8s.gcr.io/kube-scheduler '
#sync 'k8s.gcr.io/kube-proxy'
#sync 'k8s.gcr.io/kube-apiserver'
#sync 'k8s.gcr.io/etcd'
#sync 'k8s.gcr.io/coredns/coredns'
#EOF
#chmod +x sync_image.sh
#bash sync_image.sh
sync $1
